module renderer
    use, intrinsic :: iso_c_binding
    use opengl_bindings
    use font_manager
    use terminal_grid
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
        integer(GLint) :: projection_loc = -1
        integer(GLint) :: text_color_loc = -1
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

contains

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

        ! Estimate cell dimensions (use 'M' as reference)
        this%cell_width = this%font_mgr%glyphs(ichar('M'))%advance
        this%cell_height = font_size

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

        success = .true.
    end function renderer_init

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
    subroutine draw_character(this, codepoint, row, col)
        class(renderer_t), intent(inout) :: this
        integer, intent(in) :: codepoint, row, col
        type(glyph_info_t) :: glyph
        real(GLfloat) :: x, y, w, h
        real(GLfloat), target :: vertices(16)  ! 4 vertices * (2 pos + 2 tex)
        integer(c_size_t) :: vertex_size

        ! Get glyph from font manager
        glyph = this%font_mgr%get_glyph(codepoint)

        ! Set white color for Phase 1 (TODO: use cell colors)
        call glUniform3f(this%text_color_loc, 1.0, 1.0, 1.0)

        if (.not. glyph%loaded) return

        ! Calculate screen position (top-left corner)
        x = real((col - 1) * this%cell_width, GLfloat) + real(glyph%bearing_x, GLfloat)
        y = real((row - 1) * this%cell_height, GLfloat) + &
            real(this%cell_height - glyph%bearing_y, GLfloat)
        w = real(glyph%width, GLfloat)
        h = real(glyph%height, GLfloat)

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

    ! Draw terminal grid
    subroutine renderer_draw_grid(this, grid)
        class(renderer_t), intent(inout) :: this
        type(grid_t), intent(in) :: grid
        integer :: row, col
        type(cell_t) :: cell
        real(GLfloat) :: x, y, r, g, b
        real(GLfloat), target :: projection(16)

        ! Clear screen
        call glClearColor(0.0, 0.0, 0.0, 1.0)
        call glClear(GL_COLOR_BUFFER_BIT)

        ! Use shader program
        call glUseProgram(this%shader_program)

        ! Create orthographic projection matrix
        call create_ortho_matrix(projection, 0.0, real(this%window_width, GLfloat), &
                                real(this%window_height, GLfloat), 0.0, -1.0, 1.0)
        call glUniformMatrix4fv(this%projection_loc, 1, int(GL_FALSE, GLboolean), c_loc(projection))

        ! Bind font texture
        call glBindTexture(GL_TEXTURE_2D, this%font_mgr%atlas_texture)
        call glUniform1i(glGetUniformLocation(this%shader_program, "text" // c_null_char), 0)

        ! Bind VAO
        call glBindVertexArray(this%vao)

        ! Draw each character
        do row = 1, grid%rows
            do col = 1, grid%cols
                cell = grid%get_cell(row, col)

                ! Skip spaces (optimization)
                if (cell%codepoint == 32) cycle

                ! Get glyph info
                call draw_character(this, cell%codepoint, row, col)
            end do
        end do

        call glBindVertexArray(0)
        call glUseProgram(0)
    end subroutine renderer_draw_grid

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
        call this%font_mgr%destroy()
    end subroutine renderer_destroy

end module renderer
