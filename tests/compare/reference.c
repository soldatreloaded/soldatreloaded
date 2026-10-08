// The C game's simulation as the comparison sees it: a scene to make, a tick to run,
// and a probe of the world. The probe's layout is mirrored by Probe in main.odin; every
// field is 4 bytes but the random states, so the two lay out the same.

#include <stdlib.h>
#include <string.h>

#include "game/game.h"
#include "game/systems/systems.h"

typedef struct ProbeSoldier {
    uint64_t rng;
    int32_t active, team, dead, life;
    float health;
    float pos[2], old_pos[2], vel[2], forces[2], next_push[2];
    int32_t direction, stance, on_ground, jets;
    float aim[2], aim_dist;
    int32_t legs_anim, legs_frame, legs_count;
    int32_t body_anim, body_frame, body_count;
    int32_t weapon, ammo, fire_count, reload_count, startup_count;
    int32_t secondary, secondary_ammo, grenades;
    int32_t cease_fire, respawn_counter, held, hit_spray;
    int32_t kills, deaths, flags;
    int32_t idle_time, idle_antic;
    float death_pos[2], death_vel[2];
    int32_t death_part, death_fire, shot_count;
    int32_t medikit_cooldown, flag_grab_cooldown;
} ProbeSoldier;

typedef struct ProbeBullet {
    int32_t active, style, weapon, owner;
    float pos[2], vel[2], damage;
    int32_t timeout;
    float old_pos[2], initial[2], hit_spot[2];
    int32_t hit_body, ricochet_count, degrade_count;
} ProbeBullet;

typedef struct ProbeThing {
    int32_t kind, holder, timeout, resting;
    float points[4][2];
    int32_t weapon, ammo, owner, flip;
    float old_points[4][2];
    int32_t in_base, interest, last_spawn;
} ProbeThing;

typedef struct ProbeCorpse {
    int32_t active;
    float points[RAGDOLL_POINTS][2];
    float old_points[RAGDOLL_POINTS][2];
    int32_t torn, hits, dead_time, on_ground;
} ProbeCorpse;

typedef struct Probe {
    uint64_t rng;
    int32_t tick, frozen;
    int32_t time_left, ended, alpha_score, bravo_score;
    ProbeSoldier soldiers[MAX_PLAYERS];
    ProbeBullet bullets[MAX_BULLETS];
    ProbeThing things[MAX_THINGS];
    ProbeCorpse corpses[MAX_PLAYERS];
} Probe;

// What else a scenario sets up, the same in both games: mirrored by Setup in main.odin.
typedef struct Setup {
    int32_t placed; // the soldiers at `at`, not soldier 0 on an alpha spawn point and 1 a gap to its right
    float at[2][2];
    float health[2]; // 0 leaves it full
    int32_t flag;    // the flag of this kind (the port's number) moved, pole first, to `flag_at`; 0 none
    float flag_at[2];
} Setup;

// ---------------------------------------------------------------------------------
// The port's numbers

// The port has dropped some of the C game's weapons, bullet styles, things and
// animations, and numbers the rest in the same order, closed up. These are the C ids it
// has no number for; a probe of one shows -1, which no port value is.
static const int32_t DROPPED_WEAPONS[] = {WEAPON_BOW2, WEAPON_BOW, WEAPON_FLAMER, WEAPON_M2, WEAPON_CLUSTER_NADE, WEAPON_CLUSTER};
static const int32_t DROPPED_STYLES[] = {BULLET_FLAME, BULLET_ARROW, BULLET_FLAME_ARROW, BULLET_CLUSTER_NADE, BULLET_CLUSTER, BULLET_M2};
static const int32_t DROPPED_THINGS[] = {THING_FLAMER_KIT, THING_PREDATOR_KIT, THING_VEST_KIT, THING_BERSERK_KIT, THING_CLUSTER_KIT, THING_STAT_GUN};
static const int32_t DROPPED_ANIMS[] = {ANIM_RELOAD_BOW};

#define DROPPED(list) list, (int)(sizeof list / sizeof list[0])

// A C id as the port numbers it: less the dropped ids below it, -1 if it is one.
static int32_t port_id(int32_t id, const int32_t *dropped, int count)
{
    int32_t below = 0;
    for (int i = 0; i < count; i++) {
        if (dropped[i] == id) return -1;
        if (dropped[i] < id) below++;
    }
    return id - below;
}

// And back: the C id of a port number, out of `ids` of them.
static int32_t c_id(int32_t port, const int32_t *dropped, int count, int32_t ids)
{
    for (int32_t id = 0; id < ids; id++)
        if (port_id(id, dropped, count) == port) return id;
    return 0;
}

// ---------------------------------------------------------------------------------
// The scene

// A game on `map` with authority, as the C tests make one: alpha's soldier 0 on an alpha
// spawn point holding `a_weapon`, bravo's soldier 1 `gap` to its right holding `b_weapon`
// (the port's numbers); with `collide`, bullets and blasts knock dropped guns and kits
// about; and as `setup` says. Where soldier 0 was placed, for the Odin game to place its
// own.
Game *ref_scene(const char *data, const char *map, float gap, int a_weapon, int b_weapon, int collide, const Setup *setup,
                float spawn[2])
{
    Game *g = calloc(1, sizeof(Game));
    if (!g || !context_load(&g->ctx, data, map)) {
        free(g);
        return NULL;
    }
    MatchSettings settings = match_settings_for_map(g->ctx.map);
    settings.guns_collide = settings.kits_collide = collide != 0;
    game_init(g, 1, settings);
    g->world.authority = true;

    uint64_t rng = 7;
    Vec2 at = spawn_point(g->ctx.map, TEAM_ALPHA, &rng);
    Vec2 at1 = vec2(at.x + gap, at.y);
    if (setup->placed) {
        at = vec2(setup->at[0][0], setup->at[0][1]);
        at1 = vec2(setup->at[1][0], setup->at[1][1]);
    }
    WeaponId a = (WeaponId)c_id(a_weapon, DROPPED(DROPPED_WEAPONS), WEAPON_COUNT);
    WeaponId b = (WeaponId)c_id(b_weapon, DROPPED(DROPPED_WEAPONS), WEAPON_COUNT);
    soldier_spawn(&g->ctx, &g->world.soldiers[0], at, TEAM_ALPHA, GEAR_JETS, a, WEAPON_COLT);
    soldier_spawn(&g->ctx, &g->world.soldiers[1], at1, TEAM_BRAVO, GEAR_JETS, b, WEAPON_COLT);
    for (int i = 0; i < 2; i++)
        if (setup->health[i] > 0.0f) g->world.soldiers[i].health = setup->health[i];
    ThingStyle flag = (ThingStyle)c_id(setup->flag, DROPPED(DROPPED_THINGS), THING_STYLE_COUNT);
    for (int i = 0; i < MAX_THINGS && setup->flag; i++) {
        Thing *t = &g->world.things[i];
        if (t->style != flag) continue;
        Vec2 move = vec2_sub(vec2(setup->flag_at[0], setup->flag_at[1]), t->pos[0]);
        for (int k = 0; k < t->points; k++) {
            t->pos[k] = vec2_add(t->pos[k], move);
            t->old_pos[k] = vec2_add(t->old_pos[k], move);
        }
    }
    spawn[0] = at.x;
    spawn[1] = at.y;
    return g;
}

void ref_free(Game *g)
{
    if (!g) return;
    context_destroy(&g->ctx);
    free(g);
}

void ref_tick(Game *g, const Command commands[MAX_PLAYERS]) { game_tick(g, commands); }

// ---------------------------------------------------------------------------------
// The probe

static void vec(float out[2], Vec2 v)
{
    out[0] = v.x;
    out[1] = v.y;
}

static void probe_soldier(const Soldier *s, ProbeSoldier *p)
{
    if (!s->active) return;
    p->rng = s->rng;
    p->active = 1;
    p->team = s->team;
    p->dead = s->dead;
    p->life = s->life;
    p->health = s->health;
    vec(p->pos, s->pos);
    vec(p->old_pos, s->old_pos);
    vec(p->vel, s->vel);
    vec(p->forces, s->forces);
    vec(p->next_push, s->next_push);
    p->direction = s->direction;
    p->stance = s->stance;
    p->on_ground = s->on_ground;
    p->jets = s->jets;
    vec(p->aim, s->aim);
    p->aim_dist = s->aim_dist;
    p->legs_anim = port_id(s->legs.id, DROPPED(DROPPED_ANIMS));
    p->legs_frame = s->legs.frame;
    p->legs_count = s->legs.count;
    p->body_anim = port_id(s->body.id, DROPPED(DROPPED_ANIMS));
    p->body_frame = s->body.frame;
    p->body_count = s->body.count;
    p->weapon = port_id(s->weapon.id, DROPPED(DROPPED_WEAPONS));
    p->ammo = s->weapon.ammo;
    p->fire_count = s->weapon.fire_count;
    p->reload_count = s->weapon.reload_count;
    p->startup_count = s->weapon.startup_count;
    p->secondary = port_id(s->secondary.id, DROPPED(DROPPED_WEAPONS));
    p->secondary_ammo = s->secondary.ammo;
    p->grenades = s->grenades;
    p->cease_fire = s->cease_fire_counter;
    p->respawn_counter = s->respawn_counter;
    p->held = s->held;
    p->hit_spray = s->hit_spray;
    p->kills = s->kills;
    p->deaths = s->deaths;
    p->flags = s->flags;
    p->idle_time = s->idle.time;
    p->idle_antic = s->idle.random;
    vec(p->death_pos, s->death_pos);
    vec(p->death_vel, s->death_vel);
    p->death_part = s->death_part;
    p->death_fire = s->death_fire;
    p->shot_count = (int32_t)s->shot_count;
    p->medikit_cooldown = s->medikit_cooldown;
    p->flag_grab_cooldown = s->flag_grab_cooldown;
}

void ref_probe(const Game *g, Probe *p)
{
    memset(p, 0, sizeof *p);
    const World *w = &g->world;
    p->rng = w->rng;
    p->tick = (int32_t)w->tick;
    p->frozen = w->rules.frozen;
    p->time_left = g->match.time_left;
    p->ended = g->match.state == MATCH_ENDED;
    p->alpha_score = g->match.scores[TEAM_ALPHA];
    p->bravo_score = g->match.scores[TEAM_BRAVO];

    for (int i = 0; i < MAX_PLAYERS; i++) probe_soldier(&w->soldiers[i], &p->soldiers[i]);
    for (int i = 0; i < MAX_BULLETS; i++) {
        const Bullet *b = &w->bullets[i];
        if (!b->active) continue;
        p->bullets[i] = (ProbeBullet){.active = 1,
                                      .style = port_id(b->style, DROPPED(DROPPED_STYLES)),
                                      .weapon = port_id(b->weapon, DROPPED(DROPPED_WEAPONS)),
                                      .owner = b->owner,
                                      .damage = b->hit_multiply,
                                      .timeout = b->timeout};
        vec(p->bullets[i].pos, b->pos);
        vec(p->bullets[i].vel, b->vel);
        vec(p->bullets[i].old_pos, b->old_pos);
        vec(p->bullets[i].initial, b->initial);
        vec(p->bullets[i].hit_spot, b->hit_spot);
        p->bullets[i].hit_body = b->hit_body + 1; // 0 for none, as the others' ids
        p->bullets[i].ricochet_count = b->ricochet_count;
        p->bullets[i].degrade_count = b->degrade_count;
    }
    for (int i = 0; i < MAX_THINGS; i++) {
        const Thing *t = &w->things[i];
        if (t->style == THING_NONE) continue;
        p->things[i] = (ProbeThing){.kind = port_id(t->style, DROPPED(DROPPED_THINGS)),
                                    .holder = t->holder,
                                    .timeout = t->timeout,
                                    .resting = t->is_static};
        p->things[i].weapon = port_id(t->weapon, DROPPED(DROPPED_WEAPONS));
        p->things[i].ammo = t->ammo;
        p->things[i].owner = t->owner;
        p->things[i].flip = t->flip;
        p->things[i].in_base = t->in_base;
        p->things[i].interest = t->interest;
        p->things[i].last_spawn = t->last_spawn;
        for (int k = 0; k < t->points; k++) {
            vec(p->things[i].points[k], t->pos[k]);
            vec(p->things[i].old_points[k], t->old_pos[k]);
        }
    }
    for (int i = 0; i < MAX_PLAYERS; i++) {
        const Ragdoll *r = &w->ragdolls[i];
        if (!r->active) continue;
        p->corpses[i].active = 1;
        for (int k = 0; k < RAGDOLL_POINTS; k++) {
            vec(p->corpses[i].points[k], r->pos[k]);
            vec(p->corpses[i].old_points[k], r->old_pos[k]);
        }
        p->corpses[i].torn = (int32_t)r->torn;
        p->corpses[i].hits = r->hits;
        p->corpses[i].dead_time = r->dead_time;
        p->corpses[i].on_ground = r->on_ground;
    }
}

// How big the probe is here, for the Odin side to check its mirror against.
int ref_probe_size(void) { return (int)sizeof(Probe); }
