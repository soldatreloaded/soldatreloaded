package menu

import "core:strings"
import "core:sync"
import "core:thread"

import res "../../../core/resources"

// From your Soldat 1's slow work, on a thread of its own so the game draws on while it
// runs: looking for the install where it is usually put (Steam's libraries on every
// drive, Wine's), looking through one for what mods can be made of, and making one of
// them a mod. One at a time, started, then taken once it is done, as a Folder_Pick is.
//
// The job wears a Classic of its own (res.mod_make), never the game's, which the Mods
// page may wear anew while it runs. What it gives back is the context allocator's, the
// taker's to keep or free.
Soldat_Job_Kind :: enum {
	Find,   // the installs where Soldat is usually put
	Scan,   // what in `root` mods can be made of
	Import, // `source` of `root` made a mod
}

Soldat_Job :: struct {
	thread:   ^thread.Thread,
	kind:     Soldat_Job_Kind,
	done:     bool, // atomic: the job is over, and what came of it may be read
	started:  f64,  // when, by rl.GetTime: how long it has been, said while it runs
	// what it was given, its own copies
	root:     string,
	source:   res.Soldat_Source,
	// what came of it
	installs: []string,             // Find's
	sources:  []res.Soldat_Source,  // Scan's
	name:     string,               // Import's: the mod made, or meant to be
	problem:  string,               // Import's: why it wasn't; "" if it was
}

// The job's name, and its own copies of `root` and `source`, for `kind`. Nothing if one is
// running already.
soldat_job_start :: proc(job: ^Soldat_Job, kind: Soldat_Job_Kind, started: f64, root := "", source := res.Soldat_Source{}) {
	if job.thread != nil do return
	// copied before the last job's results are freed, which they may be of
	given := source
	given.name, given.dir = strings.clone(source.name), strings.clone(source.dir)
	given_root := strings.clone(root)
	soldat_job_forget(job)
	job.kind, job.started = kind, started
	job.root, job.source = given_root, given
	sync.atomic_store(&job.done, false)
	job.thread = thread.create_and_start_with_data(job, soldat_job_run)
}

// Whether a job is running, not yet taken.
soldat_job_busy :: proc(job: ^Soldat_Job) -> bool {
	return job.thread != nil
}

// The job over: `taken`, its results in `job` to read until the next starts (its own
// copies freed then, or by soldat_job_forget).
soldat_job_take :: proc(job: ^Soldat_Job) -> (taken: bool) {
	if job.thread == nil || !sync.atomic_load(&job.done) do return false
	thread.destroy(job.thread)
	job.thread = nil
	return true
}

// The job waited for, if it runs, and what it holds freed.
soldat_job_forget :: proc(job: ^Soldat_Job) {
	if job.thread != nil {
		thread.destroy(job.thread) // waits for it
		job.thread = nil
	}
	delete(job.root)
	delete(job.source.name)
	delete(job.source.dir)
	for s in job.installs do delete(s)
	delete(job.installs)
	res.soldat_sources_destroy(job.sources)
	delete(job.name)
	delete(job.problem)
	job^ = {}
}

@(private = "file")
soldat_job_run :: proc(data: rawptr) {
	job := (^Soldat_Job)(data)
	defer free_all(context.temp_allocator) // this thread's own
	switch job.kind {
	case .Find:
		job.installs = res.soldat_installs()
	case .Scan, .Import:
		own := res.mod_make(res.MODS_DIR)
		defer res.mod_destroy(&own)
		classic := res.mod_classic(own)
		if job.kind == .Scan {
			job.sources = res.soldat_sources(job.root, classic)
			break
		}
		name, problem: string
		switch job.source.kind {
		case .Own:
			name = OWN_NAME
			problem = res.mod_import({job.root}, res.MODS_DIR, name, classic, OWN_TITLE).problem
		case .Mod:
			name = res.mod_name_from(job.source.name)
			problem = res.mod_import({job.root, job.source.dir}, res.MODS_DIR, name, classic).problem
		case .Interface:
			name, problem = res.interface_install(job.root, job.source.dir, job.source.name, res.MODS_DIR, classic)
		}
		job.name, job.problem = strings.clone(name), strings.clone(problem) // out of this thread's temp allocator
	}
	sync.atomic_store(&job.done, true)
}
