/* SPDX-License-Identifier: GPL-3.0-or-later */
/*
 * Read-only libxkbcommon state probe for the frozen Manna Cadet XKB map.
 *
 * The caller supplies the frozen keymap and its xkb include directory.  This
 * deliberately exercises libxkbcommon's compiled state APIs rather than
 * inferring client-visible selector state from symbols text.
 */

#include <stdio.h>
#include <stdlib.h>

#include <xkbcommon/xkbcommon.h>
#include <xkbcommon/xkbcommon-keysyms.h>

static void
fail(const char *message)
{
    fprintf(stderr, "MANNA-XKB-GROUP2-STATE: FAILED: %s\n", message);
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
require_consumed(struct xkb_state *state, xkb_keycode_t key,
                 xkb_mod_index_t mod, int expected, const char *message)
{
    int actual = xkb_state_mod_index_is_consumed2(
        state, key, mod, XKB_CONSUMED_MODE_XKB);

    if (actual != expected)
        fail(message);
}

static void
require_effective_layout(struct xkb_state *state, xkb_layout_index_t expected,
                         const char *message)
{
    if (xkb_state_serialize_layout(state, XKB_STATE_LAYOUT_EFFECTIVE) != expected)
        fail(message);
}

static void
require_depressed_layout(struct xkb_state *state, xkb_layout_index_t expected,
                         const char *message)
{
    if (xkb_state_serialize_layout(state, XKB_STATE_LAYOUT_DEPRESSED) != expected)
        fail(message);
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
        fail("frozen map lacks AD01");
    if (xkb_keymap_num_layouts_for_key(keymap, ad01) != 2)
        fail("AD01 does not retain both frozen XKB groups");
    for (xkb_layout_index_t layout = 0; layout < 2; ++layout) {
        const xkb_keysym_t *expected = layout == 0 ? group1 : group2;
        xkb_level_index_t levels = xkb_keymap_num_levels_for_key(
            keymap, ad01, layout);
        xkb_level_index_t expected_levels = layout == 0 ? 4 : 2;

        if (levels != expected_levels)
            fail("AD01 level count differs from frozen group shape");
        for (xkb_level_index_t level = 0; level < levels; ++level) {
            const xkb_keysym_t *syms = NULL;
            int count = xkb_keymap_key_get_syms_by_level(
                keymap, ad01, layout, level, &syms);

            if (expected[level] == XKB_KEY_NoSymbol) {
                if (count != 0)
                    fail("AD01 NoSymbol level retained a non-empty keysym list");
            } else if (count != 1 || syms[0] != expected[level]) {
                fail("AD01 symbol differs from frozen group table");
            }
        }
    }
}

int
main(int argc, char **argv)
{
    struct xkb_context *context;
    struct xkb_keymap *keymap;
    struct xkb_state *state;
    FILE *file;
    xkb_keycode_t ad01, shift, top1, top2;
    xkb_mod_index_t shift_index;

    if (argc != 3)
        fail("usage: manna-xkb-group2-state KEYMAP XKB-INCLUDE-DIRECTORY");
    file = fopen(argv[1], "rb");
    if (file == NULL)
        fail("cannot open frozen Manna keymap");
    context = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    if (context == NULL)
        fail("cannot create libxkbcommon context");
    if (!xkb_context_include_path_append(context, argv[2]))
        fail("cannot add frozen Manna XKB include directory");
    keymap = xkb_keymap_new_from_file(
        context, file, XKB_KEYMAP_FORMAT_TEXT_V1,
        XKB_KEYMAP_COMPILE_NO_FLAGS);
    fclose(file);
    if (keymap == NULL)
        fail("libxkbcommon rejected frozen Manna keymap");

    require_ad01_shape(keymap);
    ad01 = xkb_keymap_key_by_name(keymap, "AD01");
    shift = xkb_keymap_key_by_name(keymap, "LFSH");
    top1 = xkb_keymap_key_by_name(keymap, "LVL3");
    top2 = xkb_keymap_key_by_name(keymap, "LVL5");
    shift_index = xkb_keymap_mod_get_index(keymap, XKB_MOD_NAME_SHIFT);
    if (shift == XKB_KEYCODE_INVALID || top1 == XKB_KEYCODE_INVALID ||
        top2 == XKB_KEYCODE_INVALID ||
        shift_index == XKB_MOD_INVALID)
        fail("frozen map lacks a required selector or modifier");
    if (xkb_keymap_key_by_name(keymap, "ZEHA") != XKB_KEYCODE_INVALID)
        fail("the standard frozen keymap unexpectedly supplied a ZEHA keycode");
    state = xkb_state_new(keymap);
    if (state == NULL)
        fail("cannot create libxkbcommon state");

    require_effective_layout(state, 0, "initial effective layout is not Group 1");
    require_depressed_layout(state, 0, "initial depressed layout is not Group 1");
    require_symbol(state, ad01, XKB_KEY_q, "Group 1 base AD01 is not q");

    xkb_state_update_key(state, top1, XKB_KEY_DOWN);
    require_effective_layout(state, 1, "LVL3 did not select Group 2");
    require_depressed_layout(state, 1, "LVL3 did not serialize Group 2 as depressed");
    if (xkb_state_serialize_mods(state, XKB_STATE_MODS_EFFECTIVE) != 0)
        fail("LVL3 changed the effective modifier mask");
    require_symbol(state, ad01, XKB_KEY_upcaret,
                   "Group 2 AD01 is not the frozen Top symbol");
    xkb_state_update_key(state, shift, XKB_KEY_DOWN);
    if (!xkb_state_mod_index_is_active(
            state, shift_index, XKB_STATE_MODS_EFFECTIVE))
        fail("Shift did not become effective in Group 2");
    require_symbol(state, ad01, XKB_KEY_NoSymbol,
                   "Shift did not select Group 2 AD01 NoSymbol");
    require_consumed(state, ad01, shift_index, 1,
                     "Group 2 AD01 did not consume Shift");
    if ((xkb_state_mod_mask_remove_consumed(
             state, ad01, xkb_state_serialize_mods(
                 state, XKB_STATE_MODS_EFFECTIVE)) &
         ((xkb_mod_mask_t) 1 << shift_index)) != 0)
        fail("consumed Group 2 Shift remained client-visible for AD01");
    xkb_state_update_key(state, shift, XKB_KEY_UP);
    xkb_state_update_key(state, top1, XKB_KEY_UP);
    require_effective_layout(state, 0, "LVL3 release did not restore Group 1");
    require_depressed_layout(state, 0, "LVL3 release left a depressed group");
    require_symbol(state, ad01, XKB_KEY_q, "LVL3 release did not restore AD01 q");

    xkb_state_update_key(state, top2, XKB_KEY_DOWN);
    require_effective_layout(state, 1, "LVL5 did not select Group 2");
    require_depressed_layout(state, 1, "LVL5 did not serialize Group 2 as depressed");
    require_symbol(state, ad01, XKB_KEY_upcaret,
                   "LVL5 did not select Group 2 AD01 Top symbol");
    xkb_state_update_key(state, top2, XKB_KEY_UP);
    require_effective_layout(state, 0, "LVL5 release did not restore Group 1");

    xkb_state_unref(state);
    xkb_keymap_unref(keymap);
    xkb_context_unref(context);
    puts("MANNA-XKB-GROUP2-STATE: PASSED");
    return 0;
}
