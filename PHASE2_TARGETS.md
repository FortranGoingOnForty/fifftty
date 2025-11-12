# Phase 2: ANSI Color & VT220 Compliance

**Goal:** Full color support, scrollback, better VT compliance
**Timeline:** Weeks 9-14 (6 weeks)
**Status:** Not started - Ready to begin!

---

## Priority Order (Top → Bottom)

### 🔥 CRITICAL (Carry-over from Phase 1)

#### 1. Fix zsh PROMPT_SP "%" Issue
**Priority:** HIGHEST - User experience issue
**Estimated Time:** 2-3 days

**Problem:** "%" character appears above each zsh prompt

**Root Cause Analysis Needed:**
- Why isn't zsh sending `CSI 6 n` (cursor position query)?
- Is TERM environment variable being inherited correctly?
- Do we need additional terminal capabilities?

**Action Items:**
1. Add comprehensive escape sequence logging
   - Log ALL sequences received from shell
   - Log ALL sequences we send back
   - Create debug mode flag
2. Verify TERM propagation to child shell
   - Add debug output in child process
   - Check `echo $TERM` inside fortty
3. Test with different TERM values
   - `TERM=vt100`
   - `TERM=xterm`
   - `TERM=xterm-256color` (current)
4. Study how other terminals handle this
   - Examine st (suckless terminal) source
   - Examine alacritty VTE code
   - Look for PROMPT_SP handling in terminal codebases
5. Implement robust bidirectional query/response
   - Ensure CSI 6 n handler works correctly
   - Ensure CSI c (DA) handler works
   - Test with real cursor position queries

**Success Criteria:**
- ✅ No "%" marker in zsh prompts
- ✅ zsh correctly detects cursor position
- ✅ Bidirectional PTY communication verified

**Files to Modify:**
- `src/pty_manager.f90` - TERM configuration
- `src/vt_parser.f90` - CSI handlers
- Add debug logging throughout

---

#### 2. Debug Stray Escape Sequences with Arrow Keys
**Priority:** HIGH - Affects usability
**Estimated Time:** 1-2 days

**Problem:** Arrow key usage causes partial text reprints or hash-like strings

**Likely Causes:**
- Missing CSI sequence handlers
- Shell sending cursor save/restore sequences we don't handle
- DCS (Device Control String) sequences not handled properly

**Action Items:**
1. Add comprehensive escape sequence logging (same as #1)
2. Identify which sequences are being printed as text
3. Implement missing CSI handlers:
   - Cursor save/restore (ESC 7, ESC 8)
   - Delete character (ESC [ P)
   - Insert line (ESC [ L)
   - Delete line (ESC [ M)
4. Test with different shells (bash vs zsh)
5. Test with different prompts (simple vs complex)

**Success Criteria:**
- ✅ No visual artifacts when using arrow keys
- ✅ Command line remains clean during navigation
- ✅ All common CSI sequences handled

**Files to Modify:**
- `src/vt_parser.f90` - Add missing CSI handlers
- `tests/test_vt_parser.f90` - Add tests for new sequences

---

### 📊 CORE PHASE 2 FEATURES

#### 3. Bold/Italic/Underline Rendering
**Priority:** MEDIUM-HIGH
**Estimated Time:** 3-4 days

**Current State:** Attributes parsed and stored, not rendered

**Implementation Plan:**

**Bold:**
- Option A: Use brighter color variant (simplest)
  - Red (1) → Bright Red (9)
  - Algorithm: `if (bold) color_index += 8`
- Option B: Load bold font variant
  - Requires separate font file
  - More complex but better looking

**Italic:**
- Requires loading italic font variant
- FreeType italic transform as fallback
- Update font_manager to support multiple faces

**Underline:**
- Draw line below character baseline
- Use OpenGL line primitive or thin quad
- Color matches foreground color

**Action Items:**
1. Implement bold via color brightening (quick win)
2. Add underline rendering (draw line below text)
3. Research italic font loading
4. Update renderer to check attribute flags
5. Add visual tests for attributes

**Success Criteria:**
- ✅ Bold text visibly different from normal
- ✅ Underline appears below text
- ✅ Italic working (or documented as Phase 3)
- ✅ Attributes can be combined (bold+underline)

**Files to Modify:**
- `src/renderer.f90` - Attribute rendering logic
- `src/font_manager.f90` - Font variant loading (italic)
- `tests/test_colors.sh` - Add attribute tests

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

#### 6. 256-Color Support
**Priority:** MEDIUM
**Estimated Time:** 2 days

**Specification:** `ESC[38;5;{n}m` (foreground), `ESC[48;5;{n}m` (background)

**Color Index Breakdown:**
- 0-15: Standard ANSI colors (already supported)
- 16-231: 6×6×6 RGB cube
- 232-255: Grayscale ramp

**Implementation Plan:**
1. Extend color palette from 16 to 256 colors
   - Calculate RGB for cube indices (16-231)
   - Calculate RGB for grayscale (232-255)
2. Update SGR handler to parse `38;5;n` and `48;5;n`
3. Extend COLOR_PALETTE or use algorithm
4. Update renderer color lookup

**Success Criteria:**
- ✅ All 256 colors accessible
- ✅ `ls --color` shows detailed colors
- ✅ Color test scripts work

**Files to Modify:**
- `src/vt_parser.f90` - SGR parsing for 256-color
- `src/renderer.f90` - Extended palette or color calculation
- `tests/test_vt_parser.f90` - 256-color tests

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

## Phase 2 Success Criteria

From ROADMAP.md:

- [ ] Pass `vttest` basic VT100/VT220 tests
- [ ] `neofetch` displays correctly with colors
- [ ] `ranger` file manager fully functional

**Additional Goals:**
- [ ] zsh PROMPT_SP issue resolved
- [ ] No visual artifacts with arrow keys
- [ ] Bold/underline rendering works
- [ ] Scrollback buffer functional
- [ ] 256-color support working

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
