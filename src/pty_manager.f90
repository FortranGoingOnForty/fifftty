module pty_manager
    use, intrinsic :: iso_c_binding
    implicit none
    private

    ! POSIX constants
    integer(c_int), parameter :: O_RDWR = int(z'0002', c_int)
    integer(c_int), parameter :: O_NOCTTY = int(z'0100', c_int)
    integer(c_int), parameter :: O_NONBLOCK = int(z'0004', c_int)
    integer(c_int), parameter :: F_GETFL = 3
    integer(c_int), parameter :: F_SETFL = 4
    integer(c_int), parameter :: STDIN_FILENO = 0
    integer(c_int), parameter :: STDOUT_FILENO = 1
    integer(c_int), parameter :: STDERR_FILENO = 2

    ! ioctl constants for terminal window size
    integer(c_long), parameter :: TIOCSWINSZ = int(z'5414', c_long)
    ! ioctl constant for non-blocking I/O (BSD/macOS)
    integer(c_long), parameter :: FIONBIO = int(z'8004667e', c_long)
    ! ioctl constant to set controlling terminal (BSD/macOS)
    integer(c_long), parameter :: TIOCSCTTY = int(z'540E', c_long)

    ! Window size structure (struct winsize)
    type, bind(c) :: winsize_t
        integer(c_short) :: ws_row
        integer(c_short) :: ws_col
        integer(c_short) :: ws_xpixel
        integer(c_short) :: ws_ypixel
    end type winsize_t

    ! PTY manager type
    type, public :: pty_t
        integer(c_int) :: master_fd = -1  ! Master PTY file descriptor
        integer(c_int) :: child_pid = -1  ! Child process PID
        logical :: is_open = .false.
    contains
        procedure :: open => pty_open
        procedure :: close => pty_close
        procedure :: read => pty_read
        procedure :: write => pty_write
        procedure :: resize => pty_resize
    end type pty_t

    ! C function interfaces
    interface
        ! PTY functions
        function posix_openpt(flags) bind(c, name='posix_openpt')
            import :: c_int
            integer(c_int), value :: flags
            integer(c_int) :: posix_openpt
        end function posix_openpt

        function grantpt(fd) bind(c, name='grantpt')
            import :: c_int
            integer(c_int), value :: fd
            integer(c_int) :: grantpt
        end function grantpt

        function unlockpt(fd) bind(c, name='unlockpt')
            import :: c_int
            integer(c_int), value :: fd
            integer(c_int) :: unlockpt
        end function unlockpt

        function ptsname(fd) bind(c, name='ptsname')
            import :: c_int, c_ptr
            integer(c_int), value :: fd
            type(c_ptr) :: ptsname
        end function ptsname

        ! Process functions
        function c_fork() bind(c, name='fork')
            import :: c_int
            integer(c_int) :: c_fork
        end function c_fork

        function setsid() bind(c, name='setsid')
            import :: c_int
            integer(c_int) :: setsid
        end function setsid

        function c_open(pathname, flags) bind(c, name='open')
            import :: c_int, c_char
            character(kind=c_char), dimension(*) :: pathname
            integer(c_int), value :: flags
            integer(c_int) :: c_open
        end function c_open

        function dup2(oldfd, newfd) bind(c, name='dup2')
            import :: c_int
            integer(c_int), value :: oldfd, newfd
            integer(c_int) :: dup2
        end function dup2

        function c_close(fd) bind(c, name='close')
            import :: c_int
            integer(c_int), value :: fd
            integer(c_int) :: c_close
        end function c_close

        function execvp(file, argv) bind(c, name='execvp')
            import :: c_int, c_char, c_ptr
            character(kind=c_char), dimension(*) :: file
            type(c_ptr), value :: argv
            integer(c_int) :: execvp
        end function execvp

        function c_read(fd, buf, count) bind(c, name='read')
            import :: c_int, c_ptr, c_size_t
            integer(c_int), value :: fd
            type(c_ptr), value :: buf
            integer(c_size_t), value :: count
            integer(c_size_t) :: c_read
        end function c_read

        function c_write(fd, buf, count) bind(c, name='write')
            import :: c_int, c_ptr, c_size_t
            integer(c_int), value :: fd
            type(c_ptr), value :: buf
            integer(c_size_t), value :: count
            integer(c_size_t) :: c_write
        end function c_write

        function ioctl(fd, request, argp) bind(c, name='ioctl')
            import :: c_int, c_long, c_ptr
            integer(c_int), value :: fd
            integer(c_long), value :: request
            type(c_ptr), value :: argp
            integer(c_int) :: ioctl
        end function ioctl

        function fcntl(fd, cmd, arg) bind(c, name='fcntl')
            import :: c_int
            integer(c_int), value :: fd, cmd, arg
            integer(c_int) :: fcntl
        end function fcntl

        ! Environment and error handling
        function getenv(name) bind(c, name='getenv')
            import :: c_char, c_ptr
            character(kind=c_char), dimension(*) :: name
            type(c_ptr) :: getenv
        end function getenv

        function setenv(name, value, overwrite) bind(c, name='setenv')
            import :: c_char, c_int
            character(kind=c_char), dimension(*) :: name, value
            integer(c_int), value :: overwrite
            integer(c_int) :: setenv
        end function setenv

        subroutine perror(s) bind(c, name='perror')
            import :: c_char
            character(kind=c_char), dimension(*) :: s
        end subroutine perror

        ! Terminal I/O control
        function tcgetattr(fd, termios_p) bind(c, name='tcgetattr')
            import :: c_int, c_ptr
            integer(c_int), value :: fd
            type(c_ptr), value :: termios_p
            integer(c_int) :: tcgetattr
        end function tcgetattr

        function tcsetattr(fd, optional_actions, termios_p) bind(c, name='tcsetattr')
            import :: c_int, c_ptr
            integer(c_int), value :: fd, optional_actions
            type(c_ptr), value :: termios_p
            integer(c_int) :: tcsetattr
        end function tcsetattr
    end interface

    ! termios structure (simplified for our needs)
    type, bind(c) :: termios_t
        integer(c_int) :: c_iflag   ! Input flags
        integer(c_int) :: c_oflag   ! Output flags
        integer(c_int) :: c_cflag   ! Control flags
        integer(c_int) :: c_lflag   ! Local flags
        integer(c_char) :: c_cc(20) ! Control characters
    end type termios_t

    ! termios flags
    integer(c_int), parameter :: ECHO = int(o'0000010', c_int)
    integer(c_int), parameter :: ECHONL = int(o'0000100', c_int)
    integer(c_int), parameter :: TCSANOW = 0

contains

    ! Open PTY and spawn shell
    function pty_open(this, rows, cols, shell_path) result(success)
        class(pty_t), intent(inout) :: this
        integer, intent(in) :: rows, cols
        character(len=*), intent(in), optional :: shell_path
        logical :: success

        integer(c_int) :: master_fd, slave_fd, pid, status
        integer(c_int), target :: on_flag
        type(c_ptr) :: slave_name_ptr
        character(len=256) :: slave_name
        character(len=256) :: shell
        type(winsize_t), target :: ws

        success = .false.

        ! Open master PTY
        master_fd = posix_openpt(ior(O_RDWR, O_NOCTTY))
        if (master_fd < 0) then
            call perror("posix_openpt" // c_null_char)
            return
        end if

        ! Set master to non-blocking mode using ioctl FIONBIO (BSD/macOS way)
        on_flag = 1  ! non-zero = enable non-blocking
        status = ioctl(master_fd, FIONBIO, c_loc(on_flag))
        if (status < 0) then
            call perror("ioctl FIONBIO" // c_null_char)
            status = c_close(master_fd)
            return
        end if

        ! Grant access to slave
        if (grantpt(master_fd) /= 0) then
            call perror("grantpt" // c_null_char)
            status = c_close(master_fd)
            return
        end if

        ! Unlock slave
        if (unlockpt(master_fd) /= 0) then
            call perror("unlockpt" // c_null_char)
            status = c_close(master_fd)
            return
        end if

        ! Get slave name
        slave_name_ptr = ptsname(master_fd)
        if (.not. c_associated(slave_name_ptr)) then
            print *, "Error: ptsname failed"
            status = c_close(master_fd)
            return
        end if
        call c_f_string(slave_name_ptr, slave_name)

        ! Set window size
        ws%ws_row = int(rows, c_short)
        ws%ws_col = int(cols, c_short)
        ws%ws_xpixel = 0
        ws%ws_ypixel = 0
        if (ioctl(master_fd, TIOCSWINSZ, c_loc(ws)) /= 0) then
            call perror("ioctl TIOCSWINSZ" // c_null_char)
        end if

        ! Fork child process
        pid = c_fork()

        if (pid < 0) then
            call perror("fork" // c_null_char)
            status = c_close(master_fd)
            return
        else if (pid == 0) then
            ! Child process
            call child_setup(slave_name, shell_path)
            ! If we get here, exec failed
            stop 1
        else
            ! Parent process
            this%master_fd = master_fd
            this%child_pid = pid
            this%is_open = .true.
            success = .true.
        end if
    end function pty_open

    ! Child process setup (runs in child, does not return)
    subroutine child_setup(slave_name, shell_path)
        character(len=*), intent(in) :: slave_name
        character(len=*), intent(in), optional :: shell_path
        integer(c_int) :: slave_fd
        character(len=256) :: shell
        character(len=256, kind=c_char), target :: shell_cstr
        type(c_ptr), target :: argv(3)
        character(len=3, kind=c_char), target :: dash_i
        integer :: i, slen

        ! Create new session
        if (setsid() < 0) then
            call perror("setsid" // c_null_char)
            stop 1
        end if

        ! Open slave PTY
        slave_fd = c_open(trim(slave_name) // c_null_char, O_RDWR)
        if (slave_fd < 0) then
            call perror("open slave" // c_null_char)
            stop 1
        end if

        ! Make this the controlling terminal for the session
        ! This is critical for zsh to recognize it as an interactive terminal
        if (ioctl(slave_fd, TIOCSCTTY, c_null_ptr) < 0) then
            print *, "Warning: Failed to set controlling terminal (TIOCSCTTY)"
            ! Continue anyway, some systems don't require this
        end if

        ! Redirect stdin, stdout, stderr to slave PTY
        if (dup2(slave_fd, STDIN_FILENO) < 0) stop 1
        if (dup2(slave_fd, STDOUT_FILENO) < 0) stop 1
        if (dup2(slave_fd, STDERR_FILENO) < 0) stop 1

        ! Disable local echo on the slave PTY to prevent character doubling
        ! The shell will echo characters back, which we'll display
        call disable_pty_echo(STDIN_FILENO)

        ! Close slave fd (already duplicated)
        if (slave_fd > 2) then
            if (c_close(slave_fd) < 0) then
                call perror("close slave_fd" // c_null_char)
            end if
        end if

        ! Determine shell to run
        if (present(shell_path)) then
            shell = trim(shell_path)
        else
            ! Use SHELL environment variable or default to /bin/sh
            call get_shell_from_env(shell)
        end if

        ! Convert shell to C string
        slen = len_trim(shell)
        do i = 1, slen
            shell_cstr(i:i) = shell(i:i)
        end do
        shell_cstr(slen+1:slen+1) = c_null_char

        ! Set TERM environment variable so shell knows terminal capabilities
        if (setenv("TERM" // c_null_char, "xterm-256color" // c_null_char, 1) /= 0) then
            print *, "ERROR: Failed to set TERM environment variable"
        else
            print *, "DEBUG: Set TERM=xterm-256color for child shell"
        end if

        ! Set COLUMNS and LINES to help shell understand terminal size
        if (setenv("COLUMNS" // c_null_char, "80" // c_null_char, 1) /= 0) then
            print *, "Warning: Failed to set COLUMNS"
        end if
        if (setenv("LINES" // c_null_char, "24" // c_null_char, 1) /= 0) then
            print *, "Warning: Failed to set LINES"
        end if

        ! Allow zsh PROMPT_SP to function normally - we now handle cursor queries properly
        ! PROMPT_SP shows "%" when cursor position is unknown, which prompts terminals to respond

        ! Execute shell with -i flag (interactive)
        dash_i = "-i" // c_null_char
        argv(1) = c_loc(shell_cstr)
        argv(2) = c_loc(dash_i)
        argv(3) = c_null_ptr

        ! This does not return if successful
        if (execvp(shell_cstr, c_loc(argv)) < 0) then
            call perror("execvp" // c_null_char)
            stop 1
        end if
    end subroutine child_setup

    ! Disable local echo on PTY to prevent character doubling
    subroutine disable_pty_echo(fd)
        integer(c_int), intent(in) :: fd
        type(termios_t), target :: tio
        integer(c_int) :: status

        ! Get current terminal settings
        status = tcgetattr(fd, c_loc(tio))
        if (status /= 0) then
            call perror("tcgetattr" // c_null_char)
            return
        end if

        ! Disable ECHO and ECHONL flags
        tio%c_lflag = iand(tio%c_lflag, not(ECHO))
        tio%c_lflag = iand(tio%c_lflag, not(ECHONL))

        ! Apply settings
        status = tcsetattr(fd, TCSANOW, c_loc(tio))
        if (status /= 0) then
            call perror("tcsetattr" // c_null_char)
        end if
    end subroutine disable_pty_echo

    ! Get shell from environment
    subroutine get_shell_from_env(shell)
        character(len=*), intent(out) :: shell
        type(c_ptr) :: env_ptr

        env_ptr = getenv("SHELL" // c_null_char)
        if (c_associated(env_ptr)) then
            call c_f_string(env_ptr, shell)
        else
            shell = "/bin/sh"
        end if
    end subroutine get_shell_from_env

    ! Close PTY
    subroutine pty_close(this)
        class(pty_t), intent(inout) :: this
        integer :: status

        if (this%master_fd >= 0) then
            status = c_close(this%master_fd)
            this%master_fd = -1
        end if
        this%is_open = .false.
    end subroutine pty_close

    ! Read from PTY (returns number of bytes read, -1 on error)
    function pty_read(this, buffer, buffer_size) result(bytes_read)
        class(pty_t), intent(in) :: this
        character(len=*), intent(out) :: buffer
        integer, intent(in) :: buffer_size
        integer :: bytes_read

        integer(c_size_t) :: read_result
        character(len=1, kind=c_char), target :: c_buffer(buffer_size)

        if (.not. this%is_open) then
            bytes_read = -1
            return
        end if

        read_result = c_read(this%master_fd, c_loc(c_buffer), int(buffer_size, c_size_t))
        bytes_read = int(read_result)

        if (bytes_read > 0) then
            buffer = transfer(c_buffer(1:bytes_read), buffer)
        end if
    end function pty_read

    ! Write to PTY (returns number of bytes written, -1 on error)
    function pty_write(this, buffer, buffer_size) result(bytes_written)
        class(pty_t), intent(in) :: this
        character(len=*), intent(in) :: buffer
        integer, intent(in) :: buffer_size
        integer :: bytes_written

        integer(c_size_t) :: write_result
        character(len=1, kind=c_char), target :: c_buffer(buffer_size)

        if (.not. this%is_open) then
            bytes_written = -1
            return
        end if

        c_buffer = transfer(buffer(1:buffer_size), c_buffer)
        write_result = c_write(this%master_fd, c_loc(c_buffer), int(buffer_size, c_size_t))
        bytes_written = int(write_result)
    end function pty_write

    ! Resize PTY
    subroutine pty_resize(this, rows, cols)
        class(pty_t), intent(in) :: this
        integer, intent(in) :: rows, cols
        type(winsize_t), target :: ws

        if (.not. this%is_open) return

        ws%ws_row = int(rows, c_short)
        ws%ws_col = int(cols, c_short)
        ws%ws_xpixel = 0
        ws%ws_ypixel = 0

        if (ioctl(this%master_fd, TIOCSWINSZ, c_loc(ws)) /= 0) then
            call perror("ioctl TIOCSWINSZ resize" // c_null_char)
        end if
    end subroutine pty_resize

    ! Helper: Convert C string pointer to Fortran string
    subroutine c_f_string(c_str_ptr, f_str)
        type(c_ptr), intent(in) :: c_str_ptr
        character(len=*), intent(out) :: f_str
        character(len=1, kind=c_char), pointer :: c_str_array(:)
        integer :: i, str_len

        if (.not. c_associated(c_str_ptr)) then
            f_str = ""
            return
        end if

        ! Get the string length
        call c_f_pointer(c_str_ptr, c_str_array, [256])
        str_len = 0
        do i = 1, 256
            if (c_str_array(i) == c_null_char) exit
            str_len = i
        end do

        ! Copy to Fortran string
        f_str = ""
        do i = 1, min(str_len, len(f_str))
            f_str(i:i) = c_str_array(i)
        end do
    end subroutine c_f_string

end module pty_manager
