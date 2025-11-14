# Phase 2: ANSI Color & VT220 Compliance

**Goal:** Full color support, scrollback, better VT compliance
**Timeline:** Weeks 9-14 (6 weeks)
**Status:** IN PROGRESS - 60% Complete!
**Last Updated:** 2025-11-13 03:20 AM

---

## 📊 PHASE 2 PROGRESS SUMMARY

### Completed Features ✅ (6/9)
1. ✅ Fix zsh PROMPT_SP issue - COMPLETE
2. ✅ Debug stray escape sequences - COMPLETE
3. ✅ Bold rendering - COMPLETE (via color brightening)
4. ✅ Underline rendering - COMPLETE
5. ✅ 256-color support - COMPLETE
6. ✅ B/R character cutoff bug - FIXED

### In Progress 🔨 (0/9)
*None currently active*

### Not Started ⏳ (3/9)
7. ⏳ Truecolor (24-bit RGB) support - PENDING (should be quick after 256-color)
8. ⏳ Scrollback buffer - PENDING (major feature)
9. ⏳ Full VT220 compliance - PENDING (partial work done)

### Deferred ⏸️ (2/9)
- ⏸️ Italic rendering - DEFERRED TO PHASE 3
- ⏸️ Mouse reporting - LOW PRIORITY

### Active Bugs 🐛 (1)
- 🐛 Fish shell OSC rendering artifacts - INVESTIGATING

### Commits Since Phase 2 Start: **42 commits** in 2 weeks

---

## Priority Order (Top → Bottom)

### 🔥 CRITICAL (Carry-over from Phase 1)

#### 1. Fix zsh PROMPT_SP "%" Issue ✅ COMPLETE
**Priority:** HIGHEST - User experience issue
**Time Taken:** 4 days
**Status:** ✅ RESOLVED

**Problem:** "%" character appeared above each zsh prompt

**Solution Implemented (Hybrid Approach):**

**Proper Terminal Protocol (Phase 1):**
- Implemented CSI c (Device Attributes) response: `ESC[?62;9;22c` (VT220+color)
- Implemented CSI 6 n (Cursor Position Report): `ESC[row;colR`
- Added bidirectional PTY communication via `send_response()` function
- Set `TERM=xterm-256color` for proper terminal identification

**Additional Workaround (Phase 2):**
- Used `unsetenv()` for PROMPT_SP as belt-and-suspenders (commit a135e0d)
- This disables zsh's space-padding feature entirely
- Note: Other terminals (alacritty, wezterm) rely only on proper CSI responses
- Workaround added due to initial issues with cursor position reporting timing

**Commits:**
- `a135e0d` - use unsetenv for PROMPT_SP to fully disable zsh feature
- `ec78600` - disable zsh PROMPT_SP to prevent init scrolling
- `3ef2195` - debug zsh PROMPT_SP issue - add escape sequence logging

**Success Criteria Met:**
- ✅ No "%" marker in zsh prompts
- ✅ zsh correctly detects terminal capabilities
- ✅ Bidirectional PTY communication verified

**Files Modified:**
- `src/pty_manager.f90` - Environment variable handling

---

#### 2. Debug Stray Escape Sequences with Arrow Keys ✅ COMPLETE
**Priority:** HIGH - Affects usability
**Time Taken:** 2 days
**Status:** ✅ RESOLVED

**Problem:** Arrow key usage caused partial text reprints or hash-like strings

**Solution Implemented:**
- Added missing CSI sequence handlers (commit 21a14d2)
- Implemented cursor save/restore, insert/delete operations
- Added comprehensive debug logging for escape sequences
- Fixed TIOCSWINSZ for proper terminal size handling

**Commits:**
- `21a14d2` - add missing CSI handlers, fix stray escape sequences
- `9b58389` - fix TIOCSWINSZ ioctl on slave PTY after fork
- `f1ab183` - fix TIOCSWINSZ constant for macOS
- `f7a578b` - improve TIOCSCTTY handling for macOS

**Success Criteria Met:**
- ✅ No visual artifacts when using arrow keys in zsh/bash
- ✅ Command line remains clean during navigation
- ✅ Common CSI sequences handled properly

**Files Modified:**
- `src/vt_parser.f90` - Added CSI handlers
- `src/pty_manager.f90` - Terminal size handling

---

### 🐛 ADDITIONAL BUG FIXES

#### B/R Character Rendering Issue ✅ FIXED
**Status:** ✅ RESOLVED
**Time Taken:** 2 days

**Problem:** Characters 'B' and 'R' appeared cut off on the left side

**Root Cause:** 1-pixel offset in glyph atlas generation - atlas started at position 1 instead of 0

**Solution Implemented:**
- Fixed atlas generation to start at position 0 (commit 822f824)
- Corrected Fortran 1-indexed arrays vs 0-based texture coordinates
- Added glyph bearing calculations for proper positioning (commits e76661d, 97bf32b)

**Commits:**
- `822f824` - fix B/R character cutoff - correct atlas offset
- `39946e7` - fix B/R cutoff attempt - add padding for glyphs
- `e76661d` - improve glyph positioning for negative bearings
- `97bf32b` - fix glyph cutoff and cursor visibility issues

---

#### Cursor Visibility & Positioning ✅ IMPROVED
**Status:** ✅ RESOLVED
**Time Taken:** 1 day

**Problem:** Cursor was hard to see, overlapping issues with text

**Solution Implemented:**
- Improved cursor visibility with better color contrast (commit 58362a2)
- Adjusted cursor positioning to prevent overlaps (commit aca5484)
- Fixed cursor position calculations (commits 0e29174, bd6222b)

**Commits:**
- `aca5484` - adjust cursor position to prevent overlap issues
- `58362a2` - debug colors, center glyphs, improve cursor visibility
- `0e29174` - debug bold attribute, fix cursor position

---

### 📊 CORE PHASE 2 FEATURES

#### 3. Bold/Italic/Underline Rendering ✅ MOSTLY COMPLETE
**Priority:** MEDIUM-HIGH
**Time Taken:** 3 days
**Status:** ✅ Bold & Underline DONE, Italic DEFERRED

**Solution Implemented:**

**Bold:** ✅ COMPLETE
- Implemented via color brightening algorithm (commit 34810f3)
- Algorithm: `if (bold) color_index += 8` for ANSI colors
- For RGB colors: multiply by 1.2 and clamp to 1.0
- Works with both 16-color and 256-color modes

**Underline:** ✅ COMPLETE
- Implemented OpenGL quad rendering below baseline (commit 5247c08)
- Underline color matches foreground text color
- Position adjusted to avoid text intersection (commits 055affe, e7b81c5)
- Two-pass rendering: text first, then underlines

**Italic:** ⏸️ DEFERRED TO PHASE 3
- Requires loading separate italic font face
- More complex than anticipated
- Not critical for Phase 2 completion

**Commits:**
- `34810f3` - implement bold rendering via color brightening
- `5247c08` - implement underline rendering
- `fb0552d` - fix underline texture switching, add bold debug
- `8daa455` - fix underline persistence, add attribute debug
- `e7b81c5` - fix underline rendering, two-pass draw
- `055affe` - fix underline positioning to avoid text intersection

**Success Criteria Met:**
- ✅ Bold text visibly different from normal (brighter colors)
- ✅ Underline appears below text at correct position
- ⏸️ Italic deferred to Phase 3
- ✅ Attributes can be combined (bold+underline tested)

**Files Modified:**
- `src/renderer.f90` - Bold and underline rendering logic
- `src/vt_parser.f90` - Attribute handling in SGR

---

#### 4. Scrollback Buffer
**Priority:** MEDIUM
**Estimated Time:** 2-3 days

**Specification:**
- Default: 10,000 lines
- Configurable in future phases
- Circular buffer to avoid reallocation
- Scroll with Shift+PgUp/PgDn (or mouse wheel in Phase 3)

**Implementation Plan:**
1. Extend grid_t to support history buffer
   - Add `history_buffer` array
   - Track `history_start`, `history_end` pointers
   - Implement circular buffer logic
2. Implement scroll_up_with_history()
   - When cursor at bottom and newline received
   - Move top line to history
   - Scroll visible lines up
3. Add scroll position tracking
   - `scroll_offset` = how far back we're viewing
   - 0 = viewing current (bottom)
   - N = viewing N lines back
4. Add keyboard handlers for scrolling
   - Shift+PgUp: Scroll back 1 page
   - Shift+PgDn: Scroll forward 1 page
   - Shift+Home: Jump to start of history
   - Shift+End: Jump to bottom (current)
5. Update renderer to draw from scroll offset

**Success Criteria:**
- ✅ Can scroll back through output
- ✅ 10,000 lines retained
- ✅ Scrolling doesn't affect shell input
- ✅ Smooth scrolling performance

**Files to Modify:**
- `src/terminal_grid.f90` - History buffer logic
- `src/fortty_app.f90` - Scroll key bindings
- `src/renderer.f90` - Render from scroll offset

---

#### 5. Full 16-Color ANSI Support
**Priority:** LOW (Already done!)
**Status:** ✅ COMPLETE in Phase 1

Currently support:
- ✅ 8 normal colors (30-37 fg, 40-47 bg)
- ✅ 8 bright colors (90-97 fg, 100-107 bg)

**Verification Needed:**
- Test all foreground colors
- Test all background colors
- Test color combinations
- Update test_colors.sh with comprehensive tests

---

#### 6. 256-Color Support ✅ COMPLETE
**Priority:** MEDIUM
**Time Taken:** 1 day
**Status:** ✅ RESOLVED

**Specification:** `ESC[38;5;{n}m` (foreground), `ESC[48;5;{n}m` (background)

**Solution Implemented:**
- Extended color palette from 16 to 256 colors (commit b1e4262)
- RGB cube calculation for indices 16-231: `r = 55 + 40*i, g = 55 + 40*j, b = 55 + 40*k`
- Grayscale ramp for indices 232-255: `gray = 8 + 10*(i-232)`
- Updated SGR handler to parse `38;5;n` and `48;5;n` sequences
- Algorithmic color calculation (no need for 256-element palette)

**Commits:**
- `b1e4262` - add 256-color support, remove debug output

**Success Criteria Met:**
- ✅ All 256 colors accessible and rendering correctly
- ✅ `ls --color` shows detailed colors properly
- ✅ Color gradients work smoothly

**Files Modified:**
- `src/vt_parser.f90` - SGR parsing for 256-color sequences
- `src/renderer.f90` - Color calculation algorithm

---

#### 7. 24-bit Truecolor Support
**Priority:** MEDIUM
**Estimated Time:** 1 day

**Specification:** `ESC[38;2;{r};{g};{b}m` (foreground), `ESC[48;2;{r};{g};{b}m` (background)

**Implementation Plan:**
1. Update SGR handler to parse `38;2;r;g;b` and `48;2;r;g;b`
2. Store RGB values directly in cell
   - Extend cell_t to support RGB
   - Or use special color index (e.g., 256+) with RGB table
3. Update renderer to use RGB directly

**Success Criteria:**
- ✅ Full 16 million colors supported
- ✅ `neofetch` displays correctly
- ✅ Gradients render smoothly

**Files to Modify:**
- `src/vt_parser.f90` - SGR parsing for truecolor
- `src/terminal_grid.f90` - RGB storage in cells
- `src/renderer.f90` - RGB rendering

---

#### 8. VT220 Commands
**Priority:** LOW-MEDIUM
**Estimated Time:** 3-4 days

**DEC Private Modes (ESC [ ? n h/l):**
- `?1h/l` - Application cursor keys
- `?25h/l` - Cursor visibility (show/hide)
- `?1049h/l` - Alternate screen buffer (for vim, less)
- `?2004h/l` - Bracketed paste mode

**Character Sets:**
- DEC Special Graphics (line drawing characters)
- ESC ( X, ESC ) X sequences

**Scrolling Regions:**
- `ESC [ {top} ; {bottom} r` - Set scroll region

**Insert/Delete Operations:**
- `ESC [ {n} P` - Delete character
- `ESC [ {n} @` - Insert character
- `ESC [ {n} L` - Insert line
- `ESC [ {n} M` - Delete line

**Implementation Plan:**
1. Implement cursor visibility (easy)
2. Implement application cursor keys mode
3. Add scrolling region support
4. Implement insert/delete operations
5. Add alternate screen buffer (bigger task)
6. Character set switching (DEC graphics)

**Success Criteria:**
- ✅ Cursor can be hidden/shown
- ✅ Insert/delete operations work
- ✅ Scrolling regions functional
- ✅ Basic vim operations work better

**Files to Modify:**
- `src/vt_parser.f90` - DEC mode handlers
- `src/terminal_grid.f90` - Scrolling regions, insert/delete
- `tests/test_vt_parser.f90` - VT220 tests

---

#### 9. Mouse Reporting
**Priority:** LOW
**Estimated Time:** 2-3 days

**Basic Mouse Tracking:**
- X10 mouse protocol (ESC [ ? 9 h)
- Basic button tracking (ESC [ ? 1000 h)
- SGR mouse protocol (ESC [ ? 1006 h) - modern

**Implementation Plan:**
1. Add GTK mouse event handlers
2. Convert mouse events to VT sequences
3. Send mouse events to PTY
4. Track mouse reporting mode state

**Success Criteria:**
- ✅ Mouse clicks register in vim
- ✅ Mouse clicks register in emacs
- ✅ Mouse scrolling (if implemented)

**Files to Modify:**
- `src/fortty_app.f90` - Mouse event handlers
- `src/vt_parser.f90` - Mouse mode tracking

---

## 🚨 CURRENT KNOWN ISSUES

### Fish Shell OSC Sequence Rendering Artifacts ⚠️ ACTIVE BUG
**Priority:** HIGH - Affects fish shell users
**Discovered:** 2025-11-13
**Status:** 🔍 INVESTIGATING

**Problem:**
Fish shell displays rendering artifacts - escape sequences appearing as literal text:
- Text like `[trunk`, `]`, and underscored characters visible in prompt
- Appears to be OSC (Operating System Command) sequences leaking through
- Affects fish shell specifically; bash/zsh work correctly

**Analysis:**
- Fish sends OSC 133 (semantic prompt marking) and OSC 1337 (iTerm2 proprietary)
- OSC handler exists in `vt_parser.f90` (lines 305-321) and should consume these bytes
- Handler appears correct: consumes bytes until BEL (0x07) or ESC \ terminator
- Issue may be related to:
  1. OSC content bytes escaping before terminator is reached
  2. Fish-specific escape sequence format not handled correctly
  3. Possible state machine transition issue

**Debug Evidence:**
- Debug logs show OSC sequences being detected: `ESC ]` appears repeatedly
- Sequences include: OSC 0 (title), OSC 133 (fish marks), OSC 1337 (iTerm2)
- Terminal works fine with bash and zsh

**Next Steps:**
1. Add detailed OSC content logging to see what bytes are being consumed
2. Verify OSC state transitions are correct
3. Check if fish uses non-standard OSC termination
4. Test with `TERM=xterm-256color` vs other TERM values
5. Compare fish escape sequences in other terminals (alacritty, wezterm)

**Files to Investigate:**
- `src/vt_parser.f90` - OSC state handling (lines 305-321)
- Check state transitions from STATE_OSC_STRING back to STATE_GROUND

**References:**
- Fish shell prompt documentation: https://fishshell.com/docs/current/interactive.html
- OSC 133 spec: https://gitlab.freedesktop.org/Per_Bothner/specifications/blob/master/proposals/semantic-prompts.md

---

## Phase 2 Success Criteria

From ROADMAP.md:

- [ ] Pass `vttest` basic VT100/VT220 tests
- [ ] `neofetch` displays correctly with colors
- [ ] `ranger` file manager fully functional

**Additional Goals:**
- [x] zsh PROMPT_SP issue resolved ✅
- [x] No visual artifacts with arrow keys ✅
- [x] Bold/underline rendering works ✅
- [ ] Scrollback buffer functional
- [x] 256-color support working ✅
- [ ] Fish shell OSC rendering fixed

---

## Development Strategy

**Week 1:** Critical fixes (#1, #2)
- Day 1-3: Fix zsh PROMPT_SP issue
- Day 4-5: Debug stray escape sequences

**Week 2:** Visual features (#3)
- Day 1-2: Bold rendering via color brightening
- Day 3-4: Underline rendering
- Day 5: Italic research/planning

**Week 3:** Extended colors (#6, #7)
- Day 1-2: 256-color support
- Day 3: Truecolor support
- Day 4-5: Color testing and refinement

**Week 4:** Scrollback (#4)
- Day 1-3: Implement scrollback buffer
- Day 4-5: Scroll key bindings and testing

**Week 5:** VT220 compliance (#8)
- Day 1-2: DEC private modes
- Day 3-4: Insert/delete operations
- Day 5: Scrolling regions

**Week 6:** Polish and testing
- Day 1-2: Mouse reporting (#9)
- Day 3-4: `vttest` compliance
- Day 5: Documentation and Phase 2 sign-off

---

## Testing Plan

**Automated Tests:**
- Extend unit tests for new CSI sequences
- Add tests for 256-color and truecolor
- Test attribute combinations
- Test scrollback buffer operations

**Manual Tests:**
- `vttest` - comprehensive terminal test suite
- `neofetch` - color and graphics
- `ranger` - file manager with colors
- `vim` - editor with modes
- `emacs` - another editor test
- Complex shell prompts (oh-my-zsh themes)

**Regression Tests:**
- Ensure Phase 1 tests still pass
- Verify no memory leaks introduced
- Performance benchmarks (FPS during heavy output)

---

## Files to Create/Modify

**New Files:**
- `tests/test_scrollback.f90` - Scrollback buffer tests
- `tests/test_vt220.f90` - VT220 sequence tests
- `tests/test_256color.f90` - Extended color tests

**Modified Files:**
- `src/vt_parser.f90` - Extended CSI/DEC handlers
- `src/terminal_grid.f90` - Scrollback buffer
- `src/renderer.f90` - Attribute rendering
- `src/fortty_app.f90` - Scroll/mouse handlers
- `src/font_manager.f90` - Font variants (italic)

---

## Reference Materials

**Standards:**
- VT220 Programmer Reference Manual (DEC, 1983)
- xterm ctlseqs documentation
- ECMA-48 Control Functions

**Source Code to Study:**
- xterm: src/charproc.c (CSI handling)
- alacritty: alacritty_terminal/src/ansi.rs
- libvterm: src/state.c

**Testing Tools:**
- vttest: https://invisible-island.net/vttest/
- terminal-colors: Color test scripts
- neofetch: System info with ANSI art

---

## Risk Mitigation

**High-Risk Items:**
1. **Alternate screen buffer** - Complex state management
   - Mitigation: Start simple, defer if needed
2. **Scrollback memory usage** - 10k lines × 80 cols × cell size
   - Mitigation: Profile memory, make buffer size configurable
3. **Performance with scrollback** - Rendering offset lines
   - Mitigation: Damage tracking (Phase 6), optimize rendering

**Medium-Risk Items:**
1. **zsh PROMPT_SP fix** - May require deep debugging
   - Mitigation: Timebox to 3 days, document if can't fix
2. **Font variant loading** - FreeType complexity
   - Mitigation: Use color brightening for bold, defer italic

---

## Phase 2 Completion Criteria

**All of the following must be true:**

- [x] Critical carry-over issues resolved (#1, #2)
- [ ] Bold and underline rendering works
- [ ] Scrollback buffer functional (10k lines)
- [ ] 256-color support implemented
- [ ] Truecolor support implemented
- [ ] Basic VT220 sequences handled
- [ ] vttest VT100/VT220 tests pass
- [ ] neofetch displays correctly
- [ ] ranger file manager works
- [ ] No memory leaks
- [ ] All unit tests passing
- [ ] Phase 2 documented

**Ready to Start Phase 2!** 🚀
