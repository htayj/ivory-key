/* SPDX-License-Identifier: GPL-3.0-or-later */
/*
 * libxkbcommon state probe for Ivory Key's generated selector carrier map.
 *
 * This is deliberately a selected generated-map sub-contract.  It does not
 * claim that the frozen Manna source, Kanata event delivery, or a client
 * protocol uses the same carrier bridge.
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
    int frozen = 0;

    if (argc == 2) {
        keymap_path = argv[1];
    } else if (argc == 4 && strcmp(argv[1], "--frozen") == 0) {
        frozen = 1;
        keymap_path = argv[2];
    } else {
        fail("usage: manna-xkb-group2-state GENERATED-KEYMAP | --frozen FROZEN-KEYMAP XKB-INCLUDE-DIRECTORY");
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

    require_ad01_shape(keymap);
    require_lsgt_inherited_boundary(keymap);
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
