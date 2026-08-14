/* SPDX-License-Identifier: GPL-3.0-or-later */
/*
 * libxkbcommon state probe for Ivory Key's generated selector carrier map.
 *
 * This is deliberately a selected generated-map sub-contract.  Its optional
 * Kanata input is the closed eight-record AD01 oracle output only; it does not
 * claim that arbitrary Kanata event delivery, the frozen Manna source, or a
 * client protocol uses the same carrier bridge.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <xkbcommon/xkbcommon.h>
#include <xkbcommon/xkbcommon-keysyms.h>

static void
fail(const char *message)
{
    fprintf(stderr, "GENERATED-XKB-SELECTOR-STATE: FAILED: %s\n", message);
    exit(1);
}

static void
require_symbol(struct xkb_state *state, xkb_keycode_t key,
               xkb_keysym_t expected, const char *message)
{
    if (xkb_state_key_get_one_sym(state, key) != expected)
        fail(message);
}

static void
require_layout(struct xkb_state *state, enum xkb_state_component component,
               xkb_layout_index_t expected, const char *message)
{
    if (xkb_state_serialize_layout(state, component) != expected)
        fail(message);
}

static void
require_modifier_visibility(struct xkb_state *state, xkb_keycode_t key,
                            xkb_mod_index_t modifier, int consumed,
                            const char *message)
{
    xkb_mod_mask_t effective = xkb_state_serialize_mods(
        state, XKB_STATE_MODS_EFFECTIVE);
    xkb_mod_mask_t remaining;
    int actual_consumed;

    if ((effective & ((xkb_mod_mask_t) 1 << modifier)) == 0)
        fail(message);
    actual_consumed = xkb_state_mod_index_is_consumed2(
        state, key, modifier, XKB_CONSUMED_MODE_XKB);
    if (actual_consumed != consumed)
        fail(message);
    remaining = xkb_state_mod_mask_remove_consumed(state, key, effective);
    if (consumed) {
        if ((remaining & ((xkb_mod_mask_t) 1 << modifier)) != 0)
            fail(message);
    } else if ((remaining & ((xkb_mod_mask_t) 1 << modifier)) == 0) {
        fail(message);
    }
}

static void
require_modifier_inactive(struct xkb_state *state, xkb_mod_index_t modifier,
                          const char *message)
{
    if (xkb_state_mod_index_is_active(state, modifier,
                                      XKB_STATE_MODS_EFFECTIVE))
        fail(message);
}

struct ad01_differential_case {
    const char *label;
    xkb_keysym_t symbol;
    xkb_layout_index_t layout;
    int shift;
    int level_three;
    int top;
};

struct ad01_edge_counts {
    unsigned int f_down;
    unsigned int f_up;
    unsigned int shift_down;
    unsigned int shift_up;
    unsigned int q_down;
    unsigned int q_up;
    unsigned int level_three_down;
    unsigned int level_three_up;
    unsigned int top_down;
    unsigned int top_up;
};

static void
require_ad01_differential_state(
    struct xkb_state *state, xkb_keycode_t q,
    xkb_mod_index_t shift_index, xkb_mod_index_t lock_index,
    xkb_mod_index_t mod5_index,
    const struct ad01_differential_case *test_case)
{
    xkb_mod_mask_t shift_mask = (xkb_mod_mask_t) 1 << shift_index;
    xkb_mod_mask_t lock_mask = (xkb_mod_mask_t) 1 << lock_index;
    xkb_mod_mask_t mod5_mask = (xkb_mod_mask_t) 1 << mod5_index;
    xkb_mod_mask_t expected_effective =
        (test_case->shift ? shift_mask : 0) |
        (test_case->level_three ? mod5_mask : 0);
    /* The consumed mask describes the key type's selectors, including
     * selectors which are not currently depressed.  AD01's Group1
     * FOUR_LEVEL_ALPHABETIC type consumes Shift, Lock, and LevelThree;
     * Group2's TWO_LEVEL type consumes Shift while leaving LevelThree and
     * Lock client-visible. */
    xkb_mod_mask_t expected_consumed =
        shift_mask | (test_case->top ? 0 : (lock_mask | mod5_mask));
    xkb_mod_mask_t effective = xkb_state_serialize_mods(
        state, XKB_STATE_MODS_EFFECTIVE);
    xkb_mod_mask_t consumed = xkb_state_key_get_consumed_mods2(
        state, q, XKB_CONSUMED_MODE_XKB);

    if (xkb_state_key_get_one_sym(state, q) != test_case->symbol)
        fail("AD01 differential symbol differs at Q down");
    if (xkb_state_serialize_layout(state, XKB_STATE_LAYOUT_EFFECTIVE) !=
            test_case->layout ||
        xkb_state_serialize_layout(state, XKB_STATE_LAYOUT_DEPRESSED) !=
            test_case->layout)
        fail("AD01 differential group differs at Q down");
    if (effective != expected_effective)
        fail("AD01 differential effective modifier mask differs at Q down");
    if (consumed != expected_consumed) {
        fprintf(stderr,
                "GENERATED-XKB-SELECTOR-STATE: FAILED: AD01 differential consumed modifier mask differs at Q down (%s: actual=0x%lx expected=0x%lx)\n",
                test_case->label, (unsigned long) consumed,
                (unsigned long) expected_consumed);
        exit(1);
    }
}

static void
require_ad01_differential_settled(
    struct xkb_state *state, xkb_keycode_t q,
    const struct ad01_differential_case *test_case,
    const struct ad01_edge_counts *counts,
    int f_down, int shift_down, int q_down, int level_three_down, int top_down)
{
    unsigned int plain = test_case->shift ? 0U : 1U;
    unsigned int shifted = test_case->shift ? 1U : 0U;
    unsigned int level_three = test_case->level_three ? 1U : 0U;
    unsigned int top = test_case->top ? 1U : 0U;

    if (counts->q_down != 1 || counts->q_up != 1 ||
        counts->f_down != plain || counts->f_up != plain ||
        counts->shift_down != shifted || counts->shift_up != shifted ||
        counts->level_three_down != level_three ||
        counts->level_three_up != level_three ||
        counts->top_down != top || counts->top_up != top)
        fail("AD01 differential record has the wrong edge multiplicity");
    if (f_down || shift_down || q_down || level_three_down || top_down)
        fail("AD01 differential record left a parsed edge held");
    if (xkb_state_serialize_mods(state, XKB_STATE_MODS_DEPRESSED) != 0 ||
        xkb_state_serialize_mods(state, XKB_STATE_MODS_LATCHED) != 0 ||
        xkb_state_serialize_mods(state, XKB_STATE_MODS_LOCKED) != 0 ||
        xkb_state_serialize_mods(state, XKB_STATE_MODS_EFFECTIVE) != 0)
        fail("AD01 differential record left modifier state active");
    if (xkb_state_serialize_layout(state, XKB_STATE_LAYOUT_DEPRESSED) != 0 ||
        xkb_state_serialize_layout(state, XKB_STATE_LAYOUT_LATCHED) != 0 ||
        xkb_state_serialize_layout(state, XKB_STATE_LAYOUT_LOCKED) != 0 ||
        xkb_state_serialize_layout(state, XKB_STATE_LAYOUT_EFFECTIVE) != 0)
        fail("AD01 differential record left group state active");
    if (xkb_state_key_get_one_sym(state, q) != XKB_KEY_q)
        fail("AD01 differential record did not settle to base q");
}

static void
run_ad01_differential_record(
    struct xkb_keymap *keymap, char *payload,
    const struct ad01_differential_case *test_case)
{
    struct xkb_state *state = xkb_state_new(keymap);
    struct ad01_edge_counts counts = {0};
    xkb_keycode_t f = xkb_keymap_key_by_name(keymap, "AC04");
    xkb_keycode_t q = xkb_keymap_key_by_name(keymap, "AD01");
    xkb_keycode_t shift = xkb_keymap_key_by_name(keymap, "LFSH");
    xkb_keycode_t top = xkb_keymap_key_by_name(keymap, "LVL3");
    xkb_keycode_t level_three = xkb_keymap_key_by_name(keymap, "ZEHA");
    xkb_mod_index_t shift_index = xkb_keymap_mod_get_index(
        keymap, XKB_MOD_NAME_SHIFT);
    xkb_mod_index_t lock_index = xkb_keymap_mod_get_index(
        keymap, XKB_MOD_NAME_CAPS);
    xkb_mod_index_t mod5_index = xkb_keymap_mod_get_index(keymap, "Mod5");
    int f_down = 0;
    int shift_down = 0;
    int q_down = 0;
    int level_three_down = 0;
    int top_down = 0;
    char *token = payload;

    if (state == NULL)
        fail("cannot create AD01 differential state");
    if (f == XKB_KEYCODE_INVALID || q == XKB_KEYCODE_INVALID ||
        shift == XKB_KEYCODE_INVALID || top != 92 || level_three != 93 ||
        shift_index == XKB_MOD_INVALID || lock_index == XKB_MOD_INVALID ||
        mod5_index == XKB_MOD_INVALID)
        fail("AD01 differential map lacks its closed key allocation");
    if (*token == '\0' || *token == ' ')
        fail("AD01 differential record has an empty edge sequence");

    while (token != NULL) {
        char *next = strchr(token, ' ');

        if (next != NULL) {
            if (next == token || next[1] == '\0' || next[1] == ' ')
                fail("AD01 differential record has noncanonical spacing");
            *next = '\0';
        }
        if (strcmp(token, "dn:F") == 0) {
            if (f_down)
                fail("AD01 differential repeats F down");
            f_down = 1;
            counts.f_down++;
            xkb_state_update_key(state, f, XKB_KEY_DOWN);
        } else if (strcmp(token, "up:F") == 0) {
            if (!f_down)
                fail("AD01 differential has F up without down");
            f_down = 0;
            counts.f_up++;
            xkb_state_update_key(state, f, XKB_KEY_UP);
        } else if (strcmp(token, "dn:LShift") == 0) {
            if (shift_down)
                fail("AD01 differential repeats LShift down");
            shift_down = 1;
            counts.shift_down++;
            xkb_state_update_key(state, shift, XKB_KEY_DOWN);
        } else if (strcmp(token, "up:LShift") == 0) {
            if (!shift_down)
                fail("AD01 differential has LShift up without down");
            shift_down = 0;
            counts.shift_up++;
            xkb_state_update_key(state, shift, XKB_KEY_UP);
        } else if (strcmp(token, "dn:Q") == 0) {
            if (q_down || counts.q_down != 0)
                fail("AD01 differential does not contain one Q interval");
            q_down = 1;
            counts.q_down++;
            xkb_state_update_key(state, q, XKB_KEY_DOWN);
            require_ad01_differential_state(
                state, q, shift_index, lock_index, mod5_index, test_case);
        } else if (strcmp(token, "up:Q") == 0) {
            if (!q_down || counts.q_up != 0)
                fail("AD01 differential has invalid Q up");
            q_down = 0;
            counts.q_up++;
            xkb_state_update_key(state, q, XKB_KEY_UP);
        } else if (strcmp(token, "out-code:85;Press") == 0) {
            if (level_three_down)
                fail("AD01 differential repeats code 85 press");
            level_three_down = 1;
            counts.level_three_down++;
            xkb_state_update_key(state, level_three, XKB_KEY_DOWN);
        } else if (strcmp(token, "out-code:85;Release") == 0) {
            if (!level_three_down)
                fail("AD01 differential has code 85 release without press");
            level_three_down = 0;
            counts.level_three_up++;
            xkb_state_update_key(state, level_three, XKB_KEY_UP);
        } else if (strcmp(token, "out-code:84;Press") == 0) {
            if (top_down)
                fail("AD01 differential repeats code 84 press");
            top_down = 1;
            counts.top_down++;
            xkb_state_update_key(state, top, XKB_KEY_DOWN);
        } else if (strcmp(token, "out-code:84;Release") == 0) {
            if (!top_down)
                fail("AD01 differential has code 84 release without press");
            top_down = 0;
            counts.top_up++;
            xkb_state_update_key(state, top, XKB_KEY_UP);
        } else {
            fail("AD01 differential record contains an unapproved edge");
        }
        token = next == NULL ? NULL : next + 1;
    }

    require_ad01_differential_settled(
        state, q, test_case, &counts, f_down, shift_down, q_down,
        level_three_down, top_down);
    xkb_state_unref(state);
}

static void
run_ad01_differential(struct xkb_keymap *keymap, const char *records_path)
{
    static const struct ad01_differential_case cases[] = {
        {"base-owner-first-plain", XKB_KEY_q, 0, 0, 0, 0},
        {"base-foreign-first-shifted", XKB_KEY_Q, 0, 1, 0, 0},
        {"85-owner-first-plain", XKB_KEY_Greek_theta, 0, 0, 1, 0},
        {"85-foreign-first-shifted", XKB_KEY_Greek_THETA, 0, 1, 1, 0},
        {"84-owner-first-plain", XKB_KEY_upcaret, 1, 0, 0, 1},
        {"84-foreign-first-shifted", XKB_KEY_NoSymbol, 1, 1, 0, 1},
        {"85+84-owner-first-plain", XKB_KEY_upcaret, 1, 0, 1, 1},
        {"85+84-foreign-first-shifted", XKB_KEY_NoSymbol, 1, 1, 1, 1}
    };
    FILE *records = fopen(records_path, "rb");
    char line[1024];

    if (records == NULL)
        fail("cannot open AD01 differential records");
    for (size_t index = 0; index < sizeof(cases) / sizeof(cases[0]); ++index) {
        char *first_tab;
        char *second_tab;
        size_t length;

        if (fgets(line, sizeof(line), records) == NULL)
            fail("AD01 differential record set ended early");
        length = strlen(line);
        if (length == 0 || line[length - 1] != '\n')
            fail("AD01 differential record is unterminated or oversized");
        line[--length] = '\0';
        if (length > 0 && line[length - 1] == '\r')
            fail("AD01 differential record uses a noncanonical line ending");
        first_tab = strchr(line, '\t');
        if (first_tab == NULL)
            fail("AD01 differential record lacks its first delimiter");
        *first_tab = '\0';
        second_tab = strchr(first_tab + 1, '\t');
        if (second_tab == NULL || strchr(second_tab + 1, '\t') != NULL)
            fail("AD01 differential record does not have exactly three fields");
        *second_tab = '\0';
        if (strcmp(line, "IVORY-KEY-AD01-DIFFERENTIAL") != 0)
            fail("AD01 differential record has an unknown tag");
        if (strcmp(first_tab + 1, cases[index].label) != 0)
            fail("AD01 differential record label/order differs");
        run_ad01_differential_record(keymap, second_tab + 1, &cases[index]);
    }
    if (fgets(line, sizeof(line), records) != NULL || !feof(records))
        fail("AD01 differential record set has trailing data");
    fclose(records);
}

static void
require_ad01_shape(struct xkb_keymap *keymap)
{
    static const xkb_keysym_t group1[] = {
        XKB_KEY_q, XKB_KEY_Q, XKB_KEY_Greek_theta, XKB_KEY_Greek_THETA
    };
    static const xkb_keysym_t group2[] = { XKB_KEY_upcaret, XKB_KEY_NoSymbol };
    xkb_keycode_t ad01 = xkb_keymap_key_by_name(keymap, "AD01");

    if (ad01 == XKB_KEYCODE_INVALID)
        fail("generated map lacks AD01");
    if (xkb_keymap_num_layouts_for_key(keymap, ad01) != 2)
        fail("AD01 does not retain the generated two-group table");
    for (xkb_layout_index_t layout = 0; layout < 2; ++layout) {
        const xkb_keysym_t *expected = layout == 0 ? group1 : group2;
        xkb_level_index_t levels = xkb_keymap_num_levels_for_key(
            keymap, ad01, layout);
        xkb_level_index_t expected_levels = layout == 0 ? 4 : 2;

        if (levels != expected_levels)
            fail("AD01 level count differs from generated group shape");
        for (xkb_level_index_t level = 0; level < levels; ++level) {
            const xkb_keysym_t *syms = NULL;
            int count = xkb_keymap_key_get_syms_by_level(
                keymap, ad01, layout, level, &syms);

            if (expected[level] == XKB_KEY_NoSymbol) {
                if (count != 0)
                    fail("AD01 NoSymbol level retained a non-empty keysym list");
            } else if (count != 1 || syms[0] != expected[level]) {
                fail("AD01 symbol differs from generated group table");
            }
        }
    }
}

static void
require_lsgt_inherited_boundary(struct xkb_keymap *keymap)
{
    const xkb_keysym_t *syms = NULL;
    xkb_keycode_t lsgt = xkb_keymap_key_by_name(keymap, "LSGT");
    int count;

    /*
     * The generated partial request includes pc+us, so LSGT remains the
     * inherited base-map key (code 94).  It is deliberately outside the
     * selected device-input domain: no Manna two-group selector table is
     * emitted for it, and the inherited symbols are not a claim about the
     * frozen eight-state LSGT table.
     */
    if (lsgt != 94)
        fail("generated map did not retain inherited pc+us LSGT keycode 94");
    if (xkb_keymap_num_layouts_for_key(keymap, lsgt) != 1)
        fail("generated map turned inherited LSGT into a Manna two-group table");
    count = xkb_keymap_key_get_syms_by_level(keymap, lsgt, 0, 0, &syms);
    if (count != 1 || syms[0] != XKB_KEY_less)
        fail("generated map lost inherited pc+us LSGT less symbol");
    count = xkb_keymap_key_get_syms_by_level(keymap, lsgt, 0, 1, &syms);
    if (count != 1 || syms[0] != XKB_KEY_greater)
        fail("generated map lost inherited pc+us LSGT greater symbol");
}

static void
require_lvl5_inherited_boundary(struct xkb_keymap *keymap,
                                struct xkb_state *state)
{
    const xkb_keysym_t *syms = NULL;
    xkb_keycode_t lvl5 = xkb_keymap_key_by_name(keymap, "LVL5");
    xkb_mod_index_t mod3 = xkb_keymap_mod_get_index(keymap, "Mod3");
    int count;

    /*
     * Like LSGT, LVL5 comes from pc+us.  The selected generated carrier
     * allocation names only LVL3=92 and ZEHA=93; it neither overrides nor
     * maps this inherited ISO_Level5_Shift/Mod3 key into device input.
     */
    if (lvl5 != 203 || lvl5 == 92 || lvl5 == 93 ||
        mod3 == XKB_MOD_INVALID)
        fail("generated map did not retain distinct inherited pc+us LVL5/Mod3");
    if (xkb_keymap_num_layouts_for_key(keymap, lvl5) != 1)
        fail("generated map turned inherited LVL5 into a selected group table");
    count = xkb_keymap_key_get_syms_by_level(keymap, lvl5, 0, 0, &syms);
    if (count != 1 || syms[0] != XKB_KEY_ISO_Level5_Shift)
        fail("generated map lost inherited pc+us LVL5 ISO_Level5_Shift symbol");
    xkb_state_update_key(state, lvl5, XKB_KEY_DOWN);
    if (!xkb_state_mod_index_is_active(state, mod3, XKB_STATE_MODS_EFFECTIVE))
        fail("generated inherited LVL5 did not retain Mod3 state");
    xkb_state_update_key(state, lvl5, XKB_KEY_UP);
    if (xkb_state_mod_index_is_active(state, mod3, XKB_STATE_MODS_EFFECTIVE))
        fail("generated inherited LVL5 release left Mod3 active");
}

struct semantic_modifier_case {
    const char *key_name;
    xkb_keysym_t keysym;
    const char *modifier;
};

static void
require_semantic_modifier_map(struct xkb_keymap *keymap)
{
    static const struct semantic_modifier_case cases[] = {
        {"LCTL", XKB_KEY_Control_L, "Control"},
        {"LALT", XKB_KEY_Meta_L, "Mod1"},
        {"RWIN", XKB_KEY_Hyper_L, "Mod2"},
        {"RALT", XKB_KEY_Alt_L, "Mod3"},
        {"LWIN", XKB_KEY_Super_L, "Mod4"}
    };
    xkb_keycode_t q = xkb_keymap_key_by_name(keymap, "AD01");

    if (q == XKB_KEYCODE_INVALID)
        fail("semantic modifier probe lacks AD01");
    for (size_t index = 0; index < sizeof(cases) / sizeof(cases[0]); ++index) {
        struct xkb_state *state = xkb_state_new(keymap);
        xkb_keycode_t key = xkb_keymap_key_by_name(keymap, cases[index].key_name);
        xkb_mod_index_t modifier = xkb_keymap_mod_get_index(
            keymap, cases[index].modifier);

        if (state == NULL || key == XKB_KEYCODE_INVALID ||
            modifier == XKB_MOD_INVALID)
            fail("generated map lacks one semantic modifier allocation");
        if (xkb_state_key_get_one_sym(state, key) != cases[index].keysym)
            fail("generated semantic modifier keysym differs");
        xkb_state_update_key(state, key, XKB_KEY_DOWN);
        require_modifier_visibility(
            state, q, modifier, 0,
            "generated semantic modifier was not effective and unconsumed");
        xkb_state_update_key(state, key, XKB_KEY_UP);
        require_modifier_inactive(
            state, modifier,
            "generated semantic modifier remained active after release");
        xkb_state_unref(state);
    }
}

static void
run_frozen_manna_contract(struct xkb_keymap *keymap)
{
    struct xkb_state *state;
    xkb_keycode_t ad01 = xkb_keymap_key_by_name(keymap, "AD01");
    xkb_keycode_t shift = xkb_keymap_key_by_name(keymap, "LFSH");
    xkb_keycode_t lvl3 = xkb_keymap_key_by_name(keymap, "LVL3");
    xkb_keycode_t lvl5 = xkb_keymap_key_by_name(keymap, "LVL5");
    xkb_mod_index_t shift_index = xkb_keymap_mod_get_index(
        keymap, XKB_MOD_NAME_SHIFT);

    require_ad01_shape(keymap);
    if (shift == XKB_KEYCODE_INVALID || lvl3 == XKB_KEYCODE_INVALID ||
        lvl5 == XKB_KEYCODE_INVALID || shift_index == XKB_MOD_INVALID)
        fail("frozen map lacks a required Top selector or Shift modifier");
    if (xkb_keymap_key_by_name(keymap, "ZEHA") != XKB_KEYCODE_INVALID)
        fail("the standard frozen keymap unexpectedly supplied a ZEHA keycode");
    state = xkb_state_new(keymap);
    if (state == NULL)
        fail("cannot create frozen-map libxkbcommon state");

    require_layout(state, XKB_STATE_LAYOUT_EFFECTIVE, 0,
                   "frozen initial effective layout is not Group 1");
    require_layout(state, XKB_STATE_LAYOUT_DEPRESSED, 0,
                   "frozen initial depressed layout is not Group 1");
    require_symbol(state, ad01, XKB_KEY_q,
                   "frozen Group 1 base AD01 is not q");
    xkb_state_update_key(state, lvl3, XKB_KEY_DOWN);
    require_layout(state, XKB_STATE_LAYOUT_EFFECTIVE, 1,
                   "frozen LVL3 did not select effective Group 2");
    require_layout(state, XKB_STATE_LAYOUT_DEPRESSED, 1,
                   "frozen LVL3 did not serialize Group 2 as depressed");
    require_symbol(state, ad01, XKB_KEY_upcaret,
                   "frozen LVL3 did not select Group 2 Top output");
    xkb_state_update_key(state, shift, XKB_KEY_DOWN);
    require_symbol(state, ad01, XKB_KEY_NoSymbol,
                   "frozen Group 2 Shift did not select literal NoSymbol");
    require_modifier_visibility(state, ad01, shift_index, 1,
                                "frozen Group 2 Shift was not effective and consumed");
    xkb_state_update_key(state, shift, XKB_KEY_UP);
    xkb_state_update_key(state, lvl3, XKB_KEY_UP);
    require_layout(state, XKB_STATE_LAYOUT_EFFECTIVE, 0,
                   "frozen LVL3 release did not restore Group 1");
    xkb_state_update_key(state, lvl5, XKB_KEY_DOWN);
    require_layout(state, XKB_STATE_LAYOUT_EFFECTIVE, 1,
                   "frozen LVL5 did not select effective Group 2");
    require_layout(state, XKB_STATE_LAYOUT_DEPRESSED, 1,
                   "frozen LVL5 did not serialize Group 2 as depressed");
    require_symbol(state, ad01, XKB_KEY_upcaret,
                   "frozen LVL5 did not select Group 2 Top output");
    xkb_state_update_key(state, lvl5, XKB_KEY_UP);
    require_layout(state, XKB_STATE_LAYOUT_EFFECTIVE, 0,
                   "frozen LVL5 release did not restore Group 1");
    xkb_state_unref(state);
}

int
main(int argc, char **argv)
{
    struct xkb_context *context;
    struct xkb_keymap *keymap;
    struct xkb_state *state;
    FILE *file;
    xkb_keycode_t ad01, shift, lvl3, zeha;
    xkb_mod_index_t shift_index, mod5_index;
    const char *keymap_path;
    const char *records_path = NULL;
    int differential = 0;
    int frozen = 0;
    int manna = 0;

    if (argc == 2) {
        keymap_path = argv[1];
    } else if (argc == 3 && strcmp(argv[1], "--manna") == 0) {
        manna = 1;
        keymap_path = argv[2];
    } else if (argc == 4 && strcmp(argv[1], "--frozen") == 0) {
        frozen = 1;
        keymap_path = argv[2];
    } else if (argc == 4 && strcmp(argv[1], "--kanata-ad01") == 0) {
        differential = 1;
        records_path = argv[2];
        keymap_path = argv[3];
    } else {
        fail("usage: manna-xkb-group2-state GENERATED-KEYMAP | --manna GENERATED-MANNA-KEYMAP | --frozen FROZEN-KEYMAP XKB-INCLUDE-DIRECTORY | --kanata-ad01 RECORDS GENERATED-KEYMAP");
    }
    file = fopen(keymap_path, "rb");
    if (file == NULL)
        fail("cannot open XKB keymap");
    context = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    if (context == NULL)
        fail("cannot create libxkbcommon context");
    if (frozen && !xkb_context_include_path_append(context, argv[3]))
        fail("cannot add frozen Manna XKB include directory");
    keymap = xkb_keymap_new_from_file(
        context, file, XKB_KEYMAP_FORMAT_TEXT_V1,
        XKB_KEYMAP_COMPILE_NO_FLAGS);
    fclose(file);
    if (keymap == NULL)
        fail("libxkbcommon rejected XKB keymap");

    if (frozen) {
        run_frozen_manna_contract(keymap);
        xkb_keymap_unref(keymap);
        xkb_context_unref(context);
        puts("FROZEN-MANNA-XKB-GROUP2-STATE: PASSED");
        return 0;
    }

    if (differential) {
        require_ad01_shape(keymap);
        require_lsgt_inherited_boundary(keymap);
        require_semantic_modifier_map(keymap);
        run_ad01_differential(keymap, records_path);
        xkb_keymap_unref(keymap);
        xkb_context_unref(context);
        puts("KANATA-GENERATED-XKB-AD01-DIFFERENTIAL: PASSED");
        return 0;
    }

    require_ad01_shape(keymap);
    require_lsgt_inherited_boundary(keymap);
    if (manna)
        require_semantic_modifier_map(keymap);
    ad01 = xkb_keymap_key_by_name(keymap, "AD01");
    shift = xkb_keymap_key_by_name(keymap, "LFSH");
    lvl3 = xkb_keymap_key_by_name(keymap, "LVL3");
    zeha = xkb_keymap_key_by_name(keymap, "ZEHA");
    shift_index = xkb_keymap_mod_get_index(keymap, XKB_MOD_NAME_SHIFT);
    mod5_index = xkb_keymap_mod_get_index(keymap, "Mod5");
    if (shift == XKB_KEYCODE_INVALID || lvl3 != 92 || zeha != 93 ||
        lvl3 == zeha || shift_index == XKB_MOD_INVALID ||
        mod5_index == XKB_MOD_INVALID)
        fail("generated map lacks its closed LVL3/ZEHA or modifier allocation");
    state = xkb_state_new(keymap);
    if (state == NULL)
        fail("cannot create libxkbcommon state");

    require_lvl5_inherited_boundary(keymap, state);

    require_layout(state, XKB_STATE_LAYOUT_EFFECTIVE, 0,
                   "initial effective layout is not Group 1");
    require_layout(state, XKB_STATE_LAYOUT_DEPRESSED, 0,
                   "initial depressed layout is not Group 1");
    require_symbol(state, ad01, XKB_KEY_q, "Group 1 base AD01 is not q");

    /* LVL3 alone is Top: it depresses Group2 without inheriting pc's Mod5. */
    xkb_state_update_key(state, lvl3, XKB_KEY_DOWN);
    require_layout(state, XKB_STATE_LAYOUT_EFFECTIVE, 1,
                   "LVL3 did not select effective Group 2");
    require_layout(state, XKB_STATE_LAYOUT_DEPRESSED, 1,
                   "LVL3 did not serialize Group 2 as depressed");
    require_modifier_inactive(state, mod5_index,
                              "LVL3 retained pc's inherited Mod5 modifier map");
    require_symbol(state, ad01, XKB_KEY_upcaret,
                   "LVL3 did not select Group 2 Top output");
    xkb_state_update_key(state, lvl3, XKB_KEY_UP);
    require_layout(state, XKB_STATE_LAYOUT_EFFECTIVE, 0,
                   "LVL3 release did not restore Group 1");

    /* ZEHA alone is Greek: Mod5 is effective and consumed in Group1. */
    xkb_state_update_key(state, zeha, XKB_KEY_DOWN);
    require_symbol(state, ad01, XKB_KEY_Greek_theta,
                   "ZEHA did not select Group 1 Greek output");
    require_modifier_visibility(state, ad01, mod5_index, 1,
                                "Group 1 Level3 was not effective and consumed");
    xkb_state_update_key(state, zeha, XKB_KEY_UP);
    require_modifier_inactive(state, mod5_index,
                              "ZEHA release left Mod5 active");
    require_symbol(state, ad01, XKB_KEY_q,
                   "ZEHA release did not restore Group 1 base output");

    /* Greek then Top: Group2 wins, but the held Level3 remains visible. */
    xkb_state_update_key(state, zeha, XKB_KEY_DOWN);
    xkb_state_update_key(state, lvl3, XKB_KEY_DOWN);
    require_layout(state, XKB_STATE_LAYOUT_EFFECTIVE, 1,
                   "ZEHA then LVL3 did not select effective Group 2");
    require_layout(state, XKB_STATE_LAYOUT_DEPRESSED, 1,
                   "ZEHA then LVL3 did not serialize depressed Group 2");
    require_symbol(state, ad01, XKB_KEY_upcaret,
                   "ZEHA then LVL3 did not select Top output");
    require_modifier_visibility(state, ad01, mod5_index, 0,
                                "Group 2 Level3 was not effective and client-visible");
    xkb_state_update_key(state, shift, XKB_KEY_DOWN);
    require_symbol(state, ad01, XKB_KEY_NoSymbol,
                   "Group 2 Shift did not select literal NoSymbol");
    require_modifier_visibility(state, ad01, shift_index, 1,
                                "Group 2 Shift was not effective and consumed");
    require_modifier_visibility(state, ad01, mod5_index, 0,
                                "Group 2 Level3 ceased to be client-visible under Shift");
    xkb_state_update_key(state, shift, XKB_KEY_UP);
    xkb_state_update_key(state, lvl3, XKB_KEY_UP);
    require_layout(state, XKB_STATE_LAYOUT_EFFECTIVE, 0,
                   "Top release did not restore Group1 while ZEHA stayed held");
    require_symbol(state, ad01, XKB_KEY_Greek_theta,
                   "Top release did not restore ZEHA Greek output");
    require_modifier_visibility(state, ad01, mod5_index, 1,
                                "ZEHA was not consumed again after Top release");
    xkb_state_update_key(state, zeha, XKB_KEY_UP);

    /* Top then Greek: the reverse press/release order has the same contract. */
    xkb_state_update_key(state, lvl3, XKB_KEY_DOWN);
    xkb_state_update_key(state, zeha, XKB_KEY_DOWN);
    require_layout(state, XKB_STATE_LAYOUT_EFFECTIVE, 1,
                   "LVL3 then ZEHA did not retain effective Group 2");
    require_layout(state, XKB_STATE_LAYOUT_DEPRESSED, 1,
                   "LVL3 then ZEHA did not retain depressed Group 2");
    require_symbol(state, ad01, XKB_KEY_upcaret,
                   "LVL3 then ZEHA did not retain Top output");
    require_modifier_visibility(state, ad01, mod5_index, 0,
                                "Group 2 Level3 was not visible in reverse press order");
    xkb_state_update_key(state, zeha, XKB_KEY_UP);
    require_modifier_inactive(state, mod5_index,
                              "ZEHA release while Top held left Mod5 active");
    require_symbol(state, ad01, XKB_KEY_upcaret,
                   "ZEHA release while Top held changed the Top output");
    xkb_state_update_key(state, lvl3, XKB_KEY_UP);
    require_layout(state, XKB_STATE_LAYOUT_EFFECTIVE, 0,
                   "final LVL3 release did not restore Group 1");
    require_symbol(state, ad01, XKB_KEY_q,
                   "final selector release did not restore AD01 q");

    xkb_state_unref(state);
    xkb_keymap_unref(keymap);
    xkb_context_unref(context);
    puts("GENERATED-XKB-SELECTOR-STATE: PASSED");
    return 0;
}
