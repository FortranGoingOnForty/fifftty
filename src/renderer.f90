module renderer
    use, intrinsic :: iso_c_binding
    use opengl_bindings
    use font_manager
    use terminal_grid  ! Imports ATTR_BOLD, ATTR_UNDERLINE, etc.
    implicit none
    private

    ! Vertex shader source (simple text rendering)
    character(len=*), parameter :: VERTEX_SHADER_SRC = &
        "#version 330 core" // c_new_line // &
        "layout (location = 0) in vec2 aPos;" // c_new_line // &
        "layout (location = 1) in vec2 aTexCoord;" // c_new_line // &
        "out vec2 TexCoord;" // c_new_line // &
        "uniform mat4 projection;" // c_new_line // &
        "void main() {" // c_new_line // &
        "    gl_Position = projection * vec4(aPos, 0.0, 1.0);" // c_new_line // &
        "    TexCoord = aTexCoord;" // c_new_line // &
        "}" // c_null_char

    ! Fragment shader source (sample from texture)
    character(len=*), parameter :: FRAGMENT_SHADER_SRC = &
        "#version 330 core" // c_new_line // &
        "in vec2 TexCoord;" // c_new_line // &
        "out vec4 FragColor;" // c_new_line // &
        "uniform sampler2D text;" // c_new_line // &
        "uniform vec3 textColor;" // c_new_line // &
        "void main() {" // c_new_line // &
        "    float alpha = texture(text, TexCoord).r;" // c_new_line // &
        "    FragColor = vec4(textColor, alpha);" // c_new_line // &
        "}" // c_null_char

    ! Renderer type
    type, public :: renderer_t
        integer(GLuint) :: shader_program = 0
        integer(GLuint) :: vao = 0
        integer(GLuint) :: vbo = 0
        integer(GLuint) :: white_texture = 0  ! 1x1 white texture for solid colors
        integer(GLint) :: projection_loc = -1
        integer(GLint) :: text_color_loc = -1
        integer(GLint) :: texture_loc = -1
        type(font_mgr_t) :: font_mgr
        integer :: window_width = 800
        integer :: window_height = 600
        integer :: cell_width = 0
        integer :: cell_height = 0
    contains
        procedure :: init => renderer_init
        procedure :: destroy => renderer_destroy
        procedure :: resize => renderer_resize
        procedure :: draw_grid => renderer_draw_grid
    end type renderer_t

    public :: renderer_init, renderer_destroy

    ! ANSI color palette (16 colors: 8 normal + 8 bright)
    ! Format: RGB values 0.0-1.0
    real(GLfloat), parameter :: COLOR_PALETTE(3, 16) = reshape([ &
        ! Normal colors (0-7) - darker for better bold contrast
        0.0, 0.0, 0.0,      & ! Black
        0.6, 0.0, 0.0,      & ! Red (darker)
        0.0, 0.6, 0.0,      & ! Green (darker)
        0.6, 0.6, 0.0,      & ! Yellow (darker)
        0.0, 0.0, 0.6,      & ! Blue (darker)
        0.6, 0.0, 0.6,      & ! Magenta (darker)
        0.0, 0.6, 0.6,      & ! Cyan (darker)
        0.7, 0.7, 0.7,      & ! White (darker)
        ! Bright colors (8-15) - noticeably brighter
        0.4, 0.4, 0.4,      & ! Bright Black (Gray)
        1.0, 0.2, 0.2,      & ! Bright Red
        0.2, 1.0, 0.2,      & ! Bright Green
        1.0, 1.0, 0.2,      & ! Bright Yellow
        0.3, 0.3, 1.0,      & ! Bright Blue
        1.0, 0.2, 1.0,      & ! Bright Magenta
        0.2, 1.0, 1.0,      & ! Bright Cyan
        1.0, 1.0, 1.0       & ! Bright White
    ], shape(COLOR_PALETTE))

contains

    ! Get RGB color from ANSI color index
    subroutine get_ansi_color(color_index, r, g, b)
        integer, intent(in) :: color_index
        real(GLfloat), intent(out) :: r, g, b
        integer :: idx, ir, ig, ib

        ! Default to white if COLOR_DEFAULT
        if (color_index == COLOR_DEFAULT .or. color_index < 0) then
            r = 1.0
            g = 1.0
            b = 1.0
        else if (color_index <= 15) then
            ! Standard 16 ANSI colors
            r = COLOR_PALETTE(1, color_index + 1)
            g = COLOR_PALETTE(2, color_index + 1)
            b = COLOR_PALETTE(3, color_index + 1)
        else if (color_index >= 16 .and. color_index <= 231) then
            ! 6x6x6 RGB cube (216 colors)
            idx = color_index - 16
            ir = idx / 36
            ig = mod(idx / 6, 6)
            ib = mod(idx, 6)
            ! Convert 0-5 to RGB values: 0->0, 1->95, 2->135, 3->175, 4->215, 5->255
            r = real(merge(ir * 40 + 55, 0, ir > 0)) / 255.0
            g = real(merge(ig * 40 + 55, 0, ig > 0)) / 255.0
            b = real(merge(ib * 40 + 55, 0, ib > 0)) / 255.0
        else if (color_index >= 232 .and. color_index <= 255) then
            ! Grayscale ramp (24 shades)
            idx = 8 + (color_index - 232) * 10
            r = real(idx) / 255.0
            g = real(idx) / 255.0
            b = real(idx) / 255.0
        else
            ! Default to white for invalid colors (>255)
            r = 1.0
            g = 1.0
            b = 1.0
        end if
    end subroutine get_ansi_color

    ! Initialize renderer
    function renderer_init(this, font_path, font_size, width, height) result(success)
        class(renderer_t), intent(inout) :: this
        character(len=*), intent(in) :: font_path
        integer, intent(in) :: font_size, width, height
        logical :: success

        success = .false.

        ! Initialize font manager
        if (.not. this%font_mgr%init(font_path, font_size)) then
            print *, "Error: Failed to initialize font manager"
            return
        end if

        ! Use font metrics for cell dimensions
        this%cell_width = this%font_mgr%cell_advance
        this%cell_height = this%font_mgr%line_height

        ! Compile shaders
        if (.not. compile_shaders(this)) then
            print *, "Error: Failed to compile shaders"
            return
        end if

        ! Setup vertex data
        call setup_vertex_data(this)

        ! Set viewport
        this%window_width = width
        this%window_height = height
        call glViewport(0, 0, width, height)

        ! Enable blending for text
        call glEnable(GL_BLEND)
        call glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)

        ! Create 1x1 white texture for solid color rendering (cursor, etc.)
        call create_white_texture(this)

        success = .true.
    end function renderer_init

    ! Create a 1x1 white texture for solid color rendering
    subroutine create_white_texture(this)
        class(renderer_t), intent(inout) :: this
        integer(GLubyte), target :: white_pixel(1)
        integer(GLuint), target :: tex_id
        integer(c_size_t) :: pixel_size

        white_pixel(1) = int(-1, GLubyte)  ! -1 as signed byte = 255 as unsigned byte

        call glGenTextures(1, c_loc(tex_id))
        this%white_texture = tex_id
        call glBindTexture(GL_TEXTURE_2D, this%white_texture)

        pixel_size = c_sizeof(white_pixel(1))
        call glTexImage2D(GL_TEXTURE_2D, 0, GL_RED, 1, 1, 0, GL_RED, GL_UNSIGNED_BYTE, c_loc(white_pixel))

        ! Set texture parameters
        call glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST)
        call glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST)
        call glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
        call glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)

        call glBindTexture(GL_TEXTURE_2D, 0)
    end subroutine create_white_texture

    ! Compile vertex and fragment shaders
    function compile_shaders(this) result(success)
        class(renderer_t), intent(inout) :: this
        logical :: success
        integer(GLuint) :: vertex_shader, fragment_shader
        integer(GLint), target :: compile_status
        character(len=512) :: info_log

        success = .false.

        ! Compile vertex shader
        vertex_shader = glCreateShader(GL_VERTEX_SHADER)
        if (vertex_shader == 0) return

        call compile_shader(vertex_shader, VERTEX_SHADER_SRC, compile_status, info_log)
        if (compile_status /= GL_TRUE) then
            print *, "Vertex shader compilation failed:"
            print *, trim(info_log)
            return
        end if

        ! Compile fragment shader
        fragment_shader = glCreateShader(GL_FRAGMENT_SHADER)
        if (fragment_shader == 0) return

        call compile_shader(fragment_shader, FRAGMENT_SHADER_SRC, compile_status, info_log)
        if (compile_status /= GL_TRUE) then
            print *, "Fragment shader compilation failed:"
            print *, trim(info_log)
            call glDeleteShader(vertex_shader)
            return
        end if

        ! Link shader program
        this%shader_program = glCreateProgram()
        call glAttachShader(this%shader_program, vertex_shader)
        call glAttachShader(this%shader_program, fragment_shader)
        call glLinkProgram(this%shader_program)

        ! Check linking status
        call glGetProgramiv(this%shader_program, GL_LINK_STATUS, c_loc(compile_status))
        if (compile_status /= GL_TRUE) then
            print *, "Shader program linking failed"
            call glDeleteShader(vertex_shader)
            call glDeleteShader(fragment_shader)
            return
        end if

        ! Clean up shaders (no longer needed after linking)
        call glDeleteShader(vertex_shader)
        call glDeleteShader(fragment_shader)

        ! Get uniform locations
        this%projection_loc = glGetUniformLocation(this%shader_program, "projection" // c_null_char)
        this%text_color_loc = glGetUniformLocation(this%shader_program, "textColor" // c_null_char)
        this%texture_loc = glGetUniformLocation(this%shader_program, "text" // c_null_char)

        ! Set texture sampler to texture unit 0
        call glUseProgram(this%shader_program)
        call glUniform1i(this%texture_loc, 0)
        call glUseProgram(0)

        success = .true.
    end function compile_shaders

    ! Helper to compile individual shader
    subroutine compile_shader(shader, source, status, info_log)
        integer(GLuint), intent(in) :: shader
        character(len=*), intent(in) :: source
        integer(GLint), intent(out), target :: status
        character(len=*), intent(out), target :: info_log
        type(c_ptr), target :: source_ptr
        character(len=len(source)), target :: source_copy

        source_copy = source
        source_ptr = c_loc(source_copy)

        call glShaderSource(shader, 1, c_loc(source_ptr), c_null_ptr)
        call glCompileShader(shader)
        call glGetShaderiv(shader, GL_COMPILE_STATUS, c_loc(status))

        if (status /= GL_TRUE) then
            call glGetShaderInfoLog(shader, len(info_log), c_null_ptr, c_loc(info_log))
        end if
    end subroutine compile_shader

    ! Setup vertex data for a quad
    subroutine setup_vertex_data(this)
        class(renderer_t), intent(inout) :: this
        real(GLfloat), target :: vertices(16)  ! 4 vertices * (2 pos + 2 tex)
        integer(GLuint), target :: vao, vbo
        integer(c_size_t) :: vertex_size

        ! Quad vertices (we'll transform these per-character)
        ! Position (x,y), TexCoord (s,t)
        vertices = [ &
            0.0, 0.0, 0.0, 0.0, &  ! Bottom-left
            1.0, 0.0, 1.0, 0.0, &  ! Bottom-right
            0.0, 1.0, 0.0, 1.0, &  ! Top-left
            1.0, 1.0, 1.0, 1.0 &   ! Top-right
        ]

        ! Create VAO and VBO
        call glGenVertexArrays(1, c_loc(vao))
        call glGenBuffers(1, c_loc(vbo))

        this%vao = vao
        this%vbo = vbo

        vertex_size = int(16, c_size_t) * c_sizeof(vertices(1))

        call glBindVertexArray(vao)
        call glBindBuffer(GL_ARRAY_BUFFER, vbo)
        call glBufferData(GL_ARRAY_BUFFER, vertex_size, c_loc(vertices), GL_STATIC_DRAW)

        ! Position attribute
        call glVertexAttribPointer(0_GLuint, 2_GLint, GL_FLOAT, int(GL_FALSE, GLboolean), &
                                  int(4 * c_sizeof(vertices(1)), GLsizei), c_null_ptr)
        call glEnableVertexAttribArray(0_GLuint)

        ! Texture coordinate attribute
        call glVertexAttribPointer(1_GLuint, 2_GLint, GL_FLOAT, int(GL_FALSE, GLboolean), &
                                  int(4 * c_sizeof(vertices(1)), GLsizei), &
                                  transfer(int(2 * c_sizeof(vertices(1)), c_intptr_t), c_null_ptr))
        call glEnableVertexAttribArray(1_GLuint)

        call glBindBuffer(GL_ARRAY_BUFFER, 0)
        call glBindVertexArray(0)
    end subroutine setup_vertex_data

    ! Resize viewport
    subroutine renderer_resize(this, width, height)
        class(renderer_t), intent(inout) :: this
        integer, intent(in) :: width, height

        this%window_width = width
        this%window_height = height
        call glViewport(0, 0, width, height)
    end subroutine renderer_resize

    ! Draw a single character at grid position
    subroutine draw_character(this, codepoint, row, col, fg_color, attributes)
        class(renderer_t), intent(inout) :: this
        integer, intent(in) :: codepoint, row, col, fg_color, attributes
        type(glyph_info_t) :: glyph
        real(GLfloat) :: x, y, w, h, r, g, b
        real(GLfloat), target :: vertices(16)  ! 4 vertices * (2 pos + 2 tex)
        integer(c_size_t) :: vertex_size
        integer :: actual_color

        ! Get glyph from font manager
        glyph = this%font_mgr%get_glyph(codepoint)

        if (.not. glyph%loaded) then
            ! Debug: Print which glyphs are not loading
            if (codepoint >= 65 .and. codepoint <= 122) then  ! A-Z, a-z
                print '(A,A,A,I0,A)', "WARNING: Glyph not loaded for '", char(codepoint), "' (", codepoint, ")"
            end if
            return
        end if

        ! Apply bold effect by brightening color (colors 0-7 become 8-15)
        actual_color = fg_color

        ! Handle COLOR_DEFAULT (256) - treat as white (7)
        if (actual_color == COLOR_DEFAULT) then
            actual_color = 7  ! Default to white
        end if

        if (iand(attributes, ATTR_BOLD) /= 0) then
            if (actual_color >= 0 .and. actual_color <= 7) then
                actual_color = actual_color + 8  ! Use bright variant
            end if
        end if

        ! Debug color application for "Bold Red"
        if (codepoint >= ichar('A') .and. codepoint <= ichar('Z') .and. fg_color == 1) then
            print '(A,A,A,I0,A,I0)', "DEBUG: '", char(codepoint), "' red color: ", fg_color, " -> ", actual_color
        end if

        ! Convert ANSI color index to RGB
        call get_ansi_color(actual_color, r, g, b)
        call glUniform3f(this%text_color_loc, r, g, b)

        ! Debug RGB values for red colors
        if (actual_color == 1 .or. actual_color == 9) then  ! Red or bright red
            print '(A,I0,A,3F6.2)', "DEBUG: Red color ", actual_color, " RGB: ", r, g, b
        end if

        ! Calculate screen position (top-left corner)
        ! Center glyphs in their cells to avoid cutoff
        ! Calculate cell center, then offset by half glyph width
        x = real((col - 1) * this%font_mgr%cell_advance, GLfloat) + &
            real((this%font_mgr%cell_advance - glyph%width) / 2, GLfloat)
        y = real((row - 1) * this%font_mgr%line_height, GLfloat) + &
            real(this%font_mgr%line_height - glyph%bearing_y, GLfloat)
        w = real(glyph%width, GLfloat)
        h = real(glyph%height, GLfloat)

        ! Debug glyph positioning for B and R
        if (codepoint == ichar('B') .or. codepoint == ichar('R')) then
            print '(A,A,A,F6.1,A,I0,A,I0)', "DEBUG: '", char(codepoint), "' x=", x, &
                  " bearing_x=", glyph%bearing_x, " width=", glyph%width
        end if

        ! Build vertex data: Position (x,y) + TexCoord (s,t)
        ! Triangle strip: bottom-left, bottom-right, top-left, top-right
        vertices = [ &
            x,     y + h, glyph%tex_x,                    glyph%tex_y + glyph%tex_height, &
            x + w, y + h, glyph%tex_x + glyph%tex_width, glyph%tex_y + glyph%tex_height, &
            x,     y,     glyph%tex_x,                    glyph%tex_y, &
            x + w, y,     glyph%tex_x + glyph%tex_width, glyph%tex_y &
        ]

        vertex_size = int(16, c_size_t) * c_sizeof(vertices(1))

        ! Update VBO with character quad
        call glBindBuffer(GL_ARRAY_BUFFER, this%vbo)
        call glBufferData(GL_ARRAY_BUFFER, vertex_size, c_loc(vertices), GL_DYNAMIC_DRAW)

        ! Draw the quad
        call glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)
    end subroutine draw_character

    ! Draw underline for a character position
    subroutine draw_underline(this, row, col, fg_color, attributes)
        class(renderer_t), intent(inout) :: this
        integer, intent(in) :: row, col, fg_color, attributes
        real(GLfloat) :: x, y, w, h, r, g, b
        real(GLfloat), target :: vertices(16)  ! 4 vertices * (2 pos + 2 tex)
        integer :: actual_color

        ! Apply bold effect to underline color too
        actual_color = fg_color

        ! Handle COLOR_DEFAULT (256) - treat as white (7)
        if (actual_color == COLOR_DEFAULT) then
            actual_color = 7  ! Default to white
        end if

        if (iand(attributes, ATTR_BOLD) /= 0) then
            if (actual_color >= 0 .and. actual_color <= 7) then
                actual_color = actual_color + 8
            end if
        end if

        ! Convert color to RGB
        call get_ansi_color(actual_color, r, g, b)

        ! Calculate underline position (below character baseline)
        x = real((col - 1) * this%font_mgr%cell_advance, GLfloat)
        y = real(row * this%font_mgr%line_height - 2, GLfloat)  ! 2 pixels from bottom of cell
        w = real(this%font_mgr%cell_advance, GLfloat)
        h = 1.0_GLfloat  ! 1 pixel thick line

        ! Use white texture and color it with the text color
        call glBindTexture(GL_TEXTURE_2D, this%white_texture)
        call glUniform3f(this%text_color_loc, r, g, b)

        ! Set up vertices for a thin horizontal quad (underline)
        vertices = [ &
            x,     y,     0.0_GLfloat, 0.0_GLfloat, &  ! Bottom-left
            x + w, y,     1.0_GLfloat, 0.0_GLfloat, &  ! Bottom-right
            x,     y + h, 0.0_GLfloat, 1.0_GLfloat, &  ! Top-left
            x + w, y + h, 1.0_GLfloat, 1.0_GLfloat  &  ! Top-right
        ]

        ! Draw as a quad
        call glBindVertexArray(this%vao)
        call glBindBuffer(GL_ARRAY_BUFFER, this%vbo)
        call glBufferData(GL_ARRAY_BUFFER, &
                         int(16 * 4, c_size_t), &  ! 16 floats * 4 bytes
                         c_loc(vertices), GL_DYNAMIC_DRAW)
        call glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)
        call glBindVertexArray(0)
    end subroutine draw_underline

    ! Draw terminal grid
    subroutine renderer_draw_grid(this, grid)
        class(renderer_t), intent(inout) :: this
        type(grid_t), intent(in) :: grid
        integer :: row, col
        type(cell_t) :: cell
        real(GLfloat), target :: projection(16)

        ! Clear screen to black (terminal background)
        call glClearColor(0.0, 0.0, 0.0, 1.0)
        call glClear(GL_COLOR_BUFFER_BIT)

        ! Use shader program
        call glUseProgram(this%shader_program)

        ! Create orthographic projection matrix (matches window size)
        call create_ortho_matrix(projection, 0.0, real(this%window_width, GLfloat), &
                                real(this%window_height, GLfloat), 0.0, -1.0, 1.0)
        call glUniformMatrix4fv(this%projection_loc, 1, int(GL_FALSE, GLboolean), c_loc(projection))

        ! Bind VAO
        call glBindVertexArray(this%vao)

        ! Activate texture unit 0 and bind font texture
        call glActiveTexture(GL_TEXTURE0)
        call glBindTexture(GL_TEXTURE_2D, this%font_mgr%atlas_texture)

        ! First pass: Draw all characters
        call glBindTexture(GL_TEXTURE_2D, this%font_mgr%atlas_texture)
        do row = 1, grid%rows
            do col = 1, grid%cols
                cell = grid%cells(col, row)  ! cells(col, row) not cells(row, col)

                ! Skip empty cells and spaces
                if (cell%codepoint > 0 .and. cell%codepoint /= 32) then
                    call draw_character(this, cell%codepoint, row, col, cell%fg_color, cell%attributes)
                end if
            end do
        end do

        ! Second pass: Draw all underlines (after all text is drawn)
        do row = 1, grid%rows
            do col = 1, grid%cols
                cell = grid%cells(col, row)

                ! Draw underline for any initialized cell with underline attribute
                if (cell%codepoint > 0 .and. iand(cell%attributes, ATTR_UNDERLINE) /= 0) then
                    call draw_underline(this, row, col, cell%fg_color, cell%attributes)
                end if
            end do
        end do

        ! Draw cursor if visible
        if (grid%cursor_visible) then
            call draw_cursor(this, grid%cursor_row, grid%cursor_col)
        end if

        call glBindVertexArray(0)
    end subroutine renderer_draw_grid

    ! Draw cursor at grid position
    subroutine draw_cursor(this, row, col)
        class(renderer_t), intent(inout) :: this
        integer, intent(in) :: row, col
        real(GLfloat) :: x, y, w, h
        real(GLfloat), target :: vertices(16)
        integer(c_size_t) :: vertex_size

        ! Calculate cursor position (underline style)
        ! Use font metrics for consistent positioning
        x = real((col - 1) * this%font_mgr%cell_advance, GLfloat)
        y = real(row * this%font_mgr%line_height - 3, GLfloat)  ! 3 pixels from bottom to ensure visibility
        w = real(this%font_mgr%cell_advance, GLfloat)
        h = 3.0  ! 3-pixel thick underline for better visibility

        ! Set cursor color (bright green)
        call glUniform3f(this%text_color_loc, 0.0, 1.0, 0.0)

        ! Bind white texture for solid color rendering
        ! This gives us alpha=1.0 everywhere, making cursor fully opaque
        call glBindTexture(GL_TEXTURE_2D, this%white_texture)

        ! Build vertex data for cursor rectangle
        ! Texture coords (0,0) to (1,1) sample the single white pixel
        vertices = [ &
            x,     y + h, 0.0, 0.0, &
            x + w, y + h, 1.0, 0.0, &
            x,     y,     0.0, 1.0, &
            x + w, y,     1.0, 1.0 &
        ]

        vertex_size = int(16, c_size_t) * c_sizeof(vertices(1))

        ! Update VBO and draw cursor
        call glBindBuffer(GL_ARRAY_BUFFER, this%vbo)
        call glBufferData(GL_ARRAY_BUFFER, vertex_size, c_loc(vertices), GL_DYNAMIC_DRAW)
        call glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

        ! Rebind font texture for subsequent character rendering
        call glBindTexture(GL_TEXTURE_2D, this%font_mgr%atlas_texture)
    end subroutine draw_cursor

    ! Create orthographic projection matrix
    subroutine create_ortho_matrix(matrix, left, right, bottom, top, near, far)
        real(GLfloat), intent(out) :: matrix(16)
        real(GLfloat), intent(in) :: left, right, bottom, top, near, far

        matrix = 0.0
        matrix(1)  = 2.0 / (right - left)
        matrix(6)  = 2.0 / (top - bottom)
        matrix(11) = -2.0 / (far - near)
        matrix(13) = -(right + left) / (right - left)
        matrix(14) = -(top + bottom) / (top - bottom)
        matrix(15) = -(far + near) / (far - near)
        matrix(16) = 1.0
    end subroutine create_ortho_matrix

    ! Destroy renderer
    subroutine renderer_destroy(this)
        class(renderer_t), intent(inout) :: this
        integer(GLuint), target :: tex_id

        ! Clean up textures
        if (this%white_texture /= 0) then
            tex_id = this%white_texture
            call glDeleteTextures(1, c_loc(tex_id))
        end if

        call this%font_mgr%destroy()
    end subroutine renderer_destroy

end module renderer
