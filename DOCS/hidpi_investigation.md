# HiDPI/Retina Display Scaling Investigation

## Problem Statement

When launching fortty from a laptop terminal, the window spawns on an external monitor and then auto-snaps to the Retina laptop screen (via tiling window manager). This caused:
- Font shrinking to unreadable size (~8pt instead of 12pt)
- Prompt jumping from top to middle of terminal
- Issue affected zsh and fish, but NOT bash

## Environment Details

- **Laptop**: Retina display (scale factor 2)
- **External monitor**: Standard DPI (scale factor 1)
- **Window manager**: macOS tiling WM that moves windows between monitors
- **Platform**: macOS with GTK4

## Root Causes Discovered

### 1. GTK4 Monitor Detection Bug on macOS
**What we found**: `gdk_display_get_monitor_at_surface()` returns the WRONG monitor after the tiling window manager moves the window.

**Evidence**:
```
DEBUG: System has 2 monitors:
DEBUG:   Monitor 0 scale factor: 2  (Retina)
DEBUG:   Monitor 1 scale factor: 1  (External)
DEBUG: Surface monitor query returned scale factor: 1  ← WRONG!
```

The window was physically on Monitor 0 (Retina), but GTK reported it was on Monitor 1.

**Hypothesis**: GTK4 caches the monitor assignment before the WM moves the window, and doesn't update it properly on macOS.

**Solution**: Implemented macOS-specific workaround - when HiDPI monitors exist and surface query returns scale 1, use the maximum scale factor from all monitors.

**Code**: `src/fortty_app.f90:55-122` (`query_monitor_scale_factor`)

### 2. Double-Scaling in OpenGL Renderer
**What we found**: GTK's GLArea on macOS automatically creates a HiDPI-scaled framebuffer.

**Problem**: We were multiplying dimensions by scale factor manually:
```fortran
physical_width = width * scale_factor   ! 800 * 2 = 1600
physical_height = height * scale_factor  ! 600 * 2 = 1200
renderer%init(..., physical_width, physical_height)  ! WRONG!
```

This caused double-scaling because GTK already scaled the framebuffer automatically.

**Solution**: Use LOGICAL dimensions for renderer initialization and resize:
```fortran
! GTK handles HiDPI scaling automatically for GLArea
renderer%init(..., width, height)  ! Use logical 800x600
```

**Code**: `src/fortty_app.f90:136-158, 262-272`

### 3. Timing Issue - Window Manager vs GTK Events
**What we found**: GTK fires resize event BEFORE the tiling window manager finishes moving the window.

**Event sequence**:
1. Window spawns on external monitor (scale=1)
2. GTK fires `resize` signal with scale=1
3. Tiling WM moves window to Retina display
4. We're already initialized with wrong scale factor

**Solution**: Added GTK `map` signal handler that defers initialization until AFTER the window is placed on screen:
```fortran
! Map fires AFTER WM positioning
handler_id = g_signal_connect(gl_area, "map", c_funloc(gl_map_callback), ...)
```

**Code**: `src/main.f90:110-112`, `src/fortty_app.f90:41-54`

### 4. Grid Resize Array Bounds Crash
**What we found**: When resizing from 160x66 (Retina) to 80x33 (standard), terminal crashed:
```
Fortran runtime error: Index '81' of dimension 1 of array 'this%cells' above upper bound of 80
```

**Root cause**: `grid_resize()` allocated new 80x33 array, then called `this%clear()` which iterated using OLD dimensions (160x66).

**Solution**: Update `this%rows`/`this%cols` BEFORE calling `clear()`:
```fortran
! Deallocate and reallocate with new size
deallocate(this%cells)
allocate(this%cells(new_cols, new_rows))

! Update dimensions BEFORE clearing!
this%rows = new_rows
this%cols = new_cols
call this%clear()  ! Now uses correct dimensions
```

**Code**: `src/terminal_grid.f90:172-215`

### 5. Debug Output Appearing in Terminal
**What we found**: Debug messages "DEBUG: Set TERM=xterm-256color" and "DEBUG: Unset PROMPT_SP..." appearing in terminal output, scrolling prompt to middle.

**Root cause**: `print` statements in child process executed AFTER `dup2()` redirected stdout to PTY:
```fortran
! These happen in child_setup() AFTER:
if (dup2(slave_fd, STDOUT_FILENO) < 0) stop 1  ! Line 376

! So these go to TERMINAL, not parent stdout:
print '(A)', "DEBUG: Set TERM=xterm-256color for child shell"  ! Line 433
print '(A)', "DEBUG: Unset PROMPT_SP to fully disable zsh PROMPT_SP feature"  ! Line 452
```

**Why bash wasn't affected**: Bash doesn't trigger the PROMPT_SP code path, so it didn't hit line 452.

**Solution**: Removed all `print` statements after `dup2()` in child process.

**Code**: `src/pty_manager.f90:428-446`

## What We Tried That Didn't Work

### Attempt 1: Using GTK's notify::scale-factor Signal
Initially tried listening to scale factor changes via GTK signal:
```fortran
g_signal_connect(gl_area, "notify::scale-factor", ...)
```

**Problem**: Signal fires too late or not at all on macOS when WM moves windows.

### Attempt 2: Polling Scale Factor Changes
Added polling in render loop to detect scale changes.

**Problem**: Works but introduces race conditions and complexity. The real issue was initialization, not runtime scale changes.

### Attempt 3: Disabling zsh PROMPT_SP
Tried to fix prompt positioning by disabling zsh's PROMPT_SP feature:
```fortran
ret = unsetenv("PROMPT_SP" // c_null_char)
```

**Problem**: This was treating a symptom. The real issue was debug output appearing in terminal.

## Key Learnings

### GTK4 + macOS + Tiling WMs = Edge Cases
Standard GTK4 APIs don't work correctly on macOS when tiling window managers move windows between monitors. The `gdk_display_get_monitor_at_surface()` function is fundamentally broken in this scenario.

### GLArea HiDPI Behavior is Platform-Specific
GTK's GLArea widget automatically creates HiDPI-scaled framebuffers on macOS, but this behavior might differ on Linux. Always use logical dimensions and let GTK handle the scaling.

### Terminal Initialization Must Wait for WM
Can't trust the first resize event. Must wait for `map` signal to ensure window manager has finished positioning the window.

### Child Process I/O After fork()
After `dup2()` redirects file descriptors, ALL output (including debug `print` statements) goes to the redirected location. Use a debug file descriptor opened BEFORE `dup2()` if debug output is needed.

## How Other Terminals Solve This

### Alacritty (Rust + winit)
Alacritty uses the `winit` library which properly queries the monitor after window creation. On macOS, winit uses native Cocoa APIs that are more reliable than GTK.

### Kitty (C + Python)
Kitty uses custom Cocoa code on macOS to query the monitor, completely bypassing GTK's monitor detection.

### GNOME Terminal (C + GTK)
GNOME Terminal doesn't have this issue because it's typically used on Linux where GTK's monitor detection works correctly. On macOS, users report similar issues with tiling WMs.

### VTE (GNOME's terminal widget library)
VTE uses the same GTK APIs we do but doesn't implement workarounds for macOS tiling WMs - this is a known limitation.

## Testing Notes

### Cannot Test Without Dual Monitor Setup
The issue ONLY occurs when:
1. External monitor connected
2. Tiling window manager enabled
3. Window spawns on one monitor and auto-snaps to another
4. The two monitors have different scale factors

Without this exact setup, the workaround can't be verified.

### Verification Checklist
When dual monitor setup is available:
- [ ] Launch fortty from laptop terminal
- [ ] Verify window spawns on external monitor
- [ ] Verify window auto-snaps to Retina laptop screen
- [ ] Check font size remains correct (not tiny)
- [ ] Check prompt appears at TOP of terminal (not middle)
- [ ] Test with zsh, fish, AND bash
- [ ] Verify terminal grid initializes at 160x66 on Retina (not 80x33)
- [ ] Check debug output doesn't appear in terminal

## Files Modified

- `src/fortty_app.f90` - Monitor query, deferred init, logical dimensions
- `src/gtk_bindings.f90` - GDK monitor query APIs
- `src/main.f90` - Map signal connection
- `src/pty_manager.f90` - Removed debug prints in child
- `src/terminal_grid.f90` - Fixed resize crash
- `src/renderer.f90` - Debug logging for viewport

## References

- GTK4 GDK Monitor API: https://docs.gtk.org/gdk4/class.Monitor.html
- VT100.net terminal docs: https://vt100.net
- Alacritty source (winit usage): https://github.com/alacritty/alacritty
- Kitty macOS implementation: https://github.com/kovidgoyal/kitty
