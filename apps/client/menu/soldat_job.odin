package menu

import "core:strings"
import "core:sync"
import "core:thread"

import res "../../../core/resources"

// The Mods page's slow work, on a thread of its own so the game draws on while it runs:
// making a mod, a copy of Classic (res.mod_from_classic); importing a folder of the
// player's Soldat 1 (an install, every mod made of it at once, or a mod or an interface of
// it alone: res.soldat_import); and unpacking a mod's zip. One at a time, started, then
// taken once it is done, as a Folder_Pick is.
//
// The job wears a Classic of its own (res.mod_make), never the game's, which the Mods
// page may wear anew while it runs. What it gives back is the context allocator's, the
// taker's to keep or free.
Soldat_Job_Kind :: enum {
	Create, // a mod made in mods/, a copy of Classic
	Import, // the folder at `root`, of Soldat 1, imported into mods/
	Unpack, // the zip at `root`, a mod's, unpacked into mods/
}

Soldat_Job :: struct {
	thread:   ^thread.Thread,
	kind:     Soldat_Job_Kind,
	done:     bool, // atomic: the job is over, and what came of it may be read
	started:  f64,  // when, by rl.GetTime: how long it has been, said while it runs
	root:     string, // what it was given, its own copy
	progress: res.Import_Progress, // Import's, read as it runs
	// what came of it
	imported: res.Soldat_Imported, // Import's
	name:     string,              // Create's and Unpack's: the mod made, or meant to be
	problem:  string,              // and why it wasn't; "" if it was
}

// The job, its own copy of `root`, for `kind`. Nothing if one is running already.
soldat_job_start :: proc(job: ^Soldat_Job, kind: Soldat_Job_Kind, started: f64, root: string) {
	if job.thread != nil do return
	given := strings.clone(root) // copied before the last job's results are freed, which it may be of
	soldat_job_forget(job)
	job.kind, job.started, job.root = kind, started, given
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
	res.soldat_imported_destroy(&job.imported)
	delete(job.name)
	delete(job.problem)
	job^ = {}
}

@(private = "file")
soldat_job_run :: proc(data: rawptr) {
	job := (^Soldat_Job)(data)
	defer free_all(context.temp_allocator) // this thread's own
	switch job.kind {
	case .Create:
		name, problem := res.mod_from_classic(res.MODS_DIR, context.temp_allocator)
		job.name, job.problem = strings.clone(name), strings.clone(problem) // out of this thread's temp allocator
	case .Unpack:
		name, problem := res.mod_unpack(job.root, res.MODS_DIR, allocator = context.temp_allocator)
		job.name, job.problem = strings.clone(name), strings.clone(problem) // out of this thread's temp allocator
	case .Import:
		own := res.mod_make(res.MODS_DIR)
		defer res.mod_destroy(&own)
		job.imported = res.soldat_import(job.root, res.MODS_DIR, res.mod_classic(own), &job.progress)
	}
	sync.atomic_store(&job.done, true)
}
