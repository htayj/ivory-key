/* SPDX-License-Identifier: GPL-3.0-or-later */
/*
 * Semantic libxkbcommon probe for the separately tagged external suite.
 * This program deliberately checks compiled keymap state, not source text or
 * xkbcli's exit status.  It accepts exactly one generated keymap pathname.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <xkbcommon/xkbcommon.h>
#include <xkbcommon/xkbcommon-keysyms.h>
#include <xkbcommon/xkbcommon-names.h>

static void
fail(const char *message)
{
    fprintf(stderr, "XKB-SEMANTIC-VALIDATION: FAILED: %s\n", message);
    exit(1);
}

static void
require_key_shape(struct xkb_keymap *keymap,
                  const char *name,
                  xkb_level_index_t expected_levels,
                  const xkb_keysym_t *expected_syms)
{
    xkb_keycode_t key = xkb_keymap_key_by_name(keymap, name);
    xkb_layout_index_t layouts;
    xkb_level_index_t levels;

    if (key == XKB_KEYCODE_INVALID)
        fail("generated key name is absent from the compiled keymap");
    layouts = xkb_keymap_num_layouts_for_key(keymap, key);
    if (layouts != 1)
        fail("generated key does not have exactly one XKB group");
    levels = xkb_keymap_num_levels_for_key(keymap, key, 0);
    if (levels != expected_levels)
        fail("compiled XKB level count differs from the generated plan");

    for (xkb_level_index_t level = 0; level < levels; ++level) {
        const xkb_keysym_t *syms = NULL;
        xkb_mod_mask_t masks[16];
        int count = xkb_keymap_key_get_syms_by_level(
            keymap, key, 0, level, &syms);
        size_t mask_count = xkb_keymap_key_get_mods_for_level(
            keymap, key, 0, level, masks, 16);

        if (count != 1 || syms[0] != expected_syms[level])
            fail("compiled XKB symbol differs from the generated plan");
        if (mask_count == 0 || mask_count > 16)
            fail("compiled XKB type has no inspectable modifier-to-level map");
    }
}

static void
require_no_explicit_actions(struct xkb_keymap *keymap)
{
    char *serialized = xkb_keymap_get_as_string(
        keymap, XKB_KEYMAP_FORMAT_TEXT_V1);
    const char *names[] = { "<AD01>", "<AD02>" };

    if (serialized == NULL)
        fail("compiled keymap could not be serialized for action inspection");
    for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); ++i) {
        char *start = strstr(serialized, names[i]);
        char *end;

        if (start == NULL)
            fail("generated key is absent from serialized compiled keymap");
        end = strstr(start, "};");
        if (end == NULL)
            fail("serialized generated key block is malformed");
        for (char *cursor = start;
             (cursor = strstr(cursor, "actions")) != NULL && cursor < end;
             ++cursor)
            fail("a direct generated symbol key unexpectedly has XKB actions");
    }
    free(serialized);
}

int
main(int argc, char **argv)
{
    static const xkb_keysym_t q_syms[] = { XKB_KEY_q, XKB_KEY_Q };
    static const xkb_keysym_t w_syms[] = { XKB_KEY_w };
    struct xkb_context *context;
    struct xkb_keymap *keymap;
    struct xkb_state *state;
    FILE *file;
    xkb_keycode_t q, w, shift;
    xkb_mod_index_t shift_index;
    xkb_mod_mask_t effective, q_unconsumed, w_unconsumed;

    if (argc != 2)
        fail("usage: xkb-state KEYMAP");
    file = fopen(argv[1], "rb");
    if (file == NULL)
        fail("cannot open generated keymap");
    context = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    if (context == NULL)
        fail("cannot create libxkbcommon context");
    keymap = xkb_keymap_new_from_file(
        context, file, XKB_KEYMAP_FORMAT_TEXT_V1,
        XKB_KEYMAP_COMPILE_NO_FLAGS);
    fclose(file);
    if (keymap == NULL)
        fail("libxkbcommon rejected generated keymap");

    require_key_shape(keymap, "AD01", 2, q_syms);
    require_key_shape(keymap, "AD02", 1, w_syms);
    require_no_explicit_actions(keymap);

    q = xkb_keymap_key_by_name(keymap, "AD01");
    w = xkb_keymap_key_by_name(keymap, "AD02");
    shift = xkb_keymap_key_by_name(keymap, "LFSH");
    shift_index = xkb_keymap_mod_get_index(keymap, XKB_MOD_NAME_SHIFT);
    if (shift == XKB_KEYCODE_INVALID || shift_index == XKB_MOD_INVALID)
        fail("compiled keymap lacks the standard Shift mapping");
    state = xkb_state_new(keymap);
    if (state == NULL)
        fail("cannot create libxkbcommon state");

    if (xkb_state_key_get_one_sym(state, q) != XKB_KEY_q)
        fail("unshifted two-level symbol is not q");
    xkb_state_update_key(state, shift, XKB_KEY_DOWN);
    if (!xkb_state_mod_index_is_active(
            state, shift_index, XKB_STATE_MODS_EFFECTIVE))
        fail("Shift key did not activate the Shift modifier");
    if (xkb_state_key_get_one_sym(state, q) != XKB_KEY_Q)
        fail("Shift did not select the second level");
    if (xkb_state_mod_index_is_consumed2(
            state, q, shift_index, XKB_CONSUMED_MODE_XKB) != 1)
        fail("Shift was not consumed by the two-level key");
    if (xkb_state_key_get_one_sym(state, w) != XKB_KEY_w)
        fail("Shift changed a one-level key");
    if (xkb_state_mod_index_is_consumed2(
            state, w, shift_index, XKB_CONSUMED_MODE_XKB) != 0)
        fail("Shift was consumed by a one-level key");
    effective = xkb_state_serialize_mods(state, XKB_STATE_MODS_EFFECTIVE);
    if ((effective & ((xkb_mod_mask_t) 1 << shift_index)) == 0)
        fail("effective Shift is absent from compiled client state");
    q_unconsumed = xkb_state_mod_mask_remove_consumed(state, q, effective);
    w_unconsumed = xkb_state_mod_mask_remove_consumed(state, w, effective);
    if ((q_unconsumed & ((xkb_mod_mask_t) 1 << shift_index)) != 0)
        fail("consumed Shift remained application-visible for the two-level key");
    if ((w_unconsumed & ((xkb_mod_mask_t) 1 << shift_index)) == 0)
        fail("unconsumed Shift is absent for the one-level key");
    xkb_state_update_key(state, shift, XKB_KEY_UP);
    if (xkb_state_mod_index_is_active(
            state, shift_index, XKB_STATE_MODS_EFFECTIVE))
        fail("Shift remained active after release");

    xkb_state_unref(state);
    xkb_keymap_unref(keymap);
    xkb_context_unref(context);
    puts("XKB-SEMANTIC-VALIDATION: PASSED");
    return 0;
}
