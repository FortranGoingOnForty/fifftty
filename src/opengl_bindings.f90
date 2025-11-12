module opengl_bindings
    use, intrinsic :: iso_c_binding
    implicit none

    ! OpenGL types
    integer, parameter :: GLenum = c_int
    integer, parameter :: GLuint = c_int
    integer, parameter :: GLint = c_int
    integer, parameter :: GLsizei = c_int
    integer, parameter :: GLboolean = c_signed_char
    integer, parameter :: GLbitfield = c_int
    integer, parameter :: GLfloat = c_float
    integer, parameter :: GLubyte = c_signed_char

    ! OpenGL constants
    integer(GLenum), parameter :: GL_FALSE = 0
    integer(GLenum), parameter :: GL_TRUE = 1

    ! Buffer bits
    integer(GLbitfield), parameter :: GL_COLOR_BUFFER_BIT = int(z'00004000', GLbitfield)
    integer(GLbitfield), parameter :: GL_DEPTH_BUFFER_BIT = int(z'00000100', GLbitfield)

    ! Primitives
    integer(GLenum), parameter :: GL_TRIANGLES = int(z'0004', GLenum)
    integer(GLenum), parameter :: GL_TRIANGLE_STRIP = int(z'0005', GLenum)

    ! Blending
    integer(GLenum), parameter :: GL_BLEND = int(z'0BE2', GLenum)
    integer(GLenum), parameter :: GL_SRC_ALPHA = int(z'0302', GLenum)
    integer(GLenum), parameter :: GL_ONE_MINUS_SRC_ALPHA = int(z'0303', GLenum)

    ! Textures
    integer(GLenum), parameter :: GL_TEXTURE_2D = int(z'0DE1', GLenum)
    integer(GLenum), parameter :: GL_TEXTURE_MIN_FILTER = int(z'2801', GLenum)
    integer(GLenum), parameter :: GL_TEXTURE_MAG_FILTER = int(z'2800', GLenum)
    integer(GLenum), parameter :: GL_TEXTURE_WRAP_S = int(z'2802', GLenum)
    integer(GLenum), parameter :: GL_TEXTURE_WRAP_T = int(z'2803', GLenum)
    integer(GLenum), parameter :: GL_LINEAR = int(z'2601', GLenum)
    integer(GLenum), parameter :: GL_NEAREST = int(z'2600', GLenum)
    integer(GLenum), parameter :: GL_CLAMP_TO_EDGE = int(z'812F', GLenum)
    integer(GLenum), parameter :: GL_RED = int(z'1903', GLenum)
    integer(GLenum), parameter :: GL_UNSIGNED_BYTE = int(z'1401', GLenum)
    integer(GLenum), parameter :: GL_UNPACK_ALIGNMENT = int(z'0CF5', GLenum)
    integer(GLenum), parameter :: GL_TEXTURE0 = int(z'84C0', GLenum)

    ! Shaders
    integer(GLenum), parameter :: GL_VERTEX_SHADER = int(z'8B31', GLenum)
    integer(GLenum), parameter :: GL_FRAGMENT_SHADER = int(z'8B30', GLenum)
    integer(GLenum), parameter :: GL_COMPILE_STATUS = int(z'8B81', GLenum)
    integer(GLenum), parameter :: GL_LINK_STATUS = int(z'8B82', GLenum)

    ! Buffers
    integer(GLenum), parameter :: GL_ARRAY_BUFFER = int(z'8892', GLenum)
    integer(GLenum), parameter :: GL_STATIC_DRAW = int(z'88E4', GLenum)
    integer(GLenum), parameter :: GL_DYNAMIC_DRAW = int(z'88E8', GLenum)

    ! Data types
    integer(GLenum), parameter :: GL_FLOAT = int(z'1406', GLenum)

    interface
        ! Basic OpenGL functions
        subroutine glViewport(x, y, width, height) bind(c, name='glViewport')
            import :: GLint, GLsizei
            integer(GLint), value :: x, y
            integer(GLsizei), value :: width, height
        end subroutine glViewport

        subroutine glClearColor(red, green, blue, alpha) bind(c, name='glClearColor')
            import :: GLfloat
            real(GLfloat), value :: red, green, blue, alpha
        end subroutine glClearColor

        subroutine glClear(mask) bind(c, name='glClear')
            import :: GLbitfield
            integer(GLbitfield), value :: mask
        end subroutine glClear

        subroutine glFlush() bind(c, name='glFlush')
        end subroutine glFlush

        subroutine glEnable(cap) bind(c, name='glEnable')
            import :: GLenum
            integer(GLenum), value :: cap
        end subroutine glEnable

        subroutine glBlendFunc(sfactor, dfactor) bind(c, name='glBlendFunc')
            import :: GLenum
            integer(GLenum), value :: sfactor, dfactor
        end subroutine glBlendFunc

        subroutine glPixelStorei(pname, param) bind(c, name='glPixelStorei')
            import :: GLenum, GLint
            integer(GLenum), value :: pname
            integer(GLint), value :: param
        end subroutine glPixelStorei

        ! Shader functions
        function glCreateShader(shader_type) bind(c, name='glCreateShader')
            import :: GLenum, GLuint
            integer(GLenum), value :: shader_type
            integer(GLuint) :: glCreateShader
        end function glCreateShader

        subroutine glShaderSource(shader, count, string, length) bind(c, name='glShaderSource')
            import :: GLuint, GLsizei, c_ptr
            integer(GLuint), value :: shader
            integer(GLsizei), value :: count
            type(c_ptr), value :: string
            type(c_ptr), value :: length
        end subroutine glShaderSource

        subroutine glCompileShader(shader) bind(c, name='glCompileShader')
            import :: GLuint
            integer(GLuint), value :: shader
        end subroutine glCompileShader

        subroutine glGetShaderiv(shader, pname, params) bind(c, name='glGetShaderiv')
            import :: GLuint, GLenum, c_ptr
            integer(GLuint), value :: shader
            integer(GLenum), value :: pname
            type(c_ptr), value :: params
        end subroutine glGetShaderiv

        subroutine glGetShaderInfoLog(shader, max_length, length, info_log) bind(c, name='glGetShaderInfoLog')
            import :: GLuint, GLsizei, c_ptr
            integer(GLuint), value :: shader
            integer(GLsizei), value :: max_length
            type(c_ptr), value :: length
            type(c_ptr), value :: info_log
        end subroutine glGetShaderInfoLog

        function glCreateProgram() bind(c, name='glCreateProgram')
            import :: GLuint
            integer(GLuint) :: glCreateProgram
        end function glCreateProgram

        subroutine glAttachShader(program, shader) bind(c, name='glAttachShader')
            import :: GLuint
            integer(GLuint), value :: program, shader
        end subroutine glAttachShader

        subroutine glLinkProgram(program) bind(c, name='glLinkProgram')
            import :: GLuint
            integer(GLuint), value :: program
        end subroutine glLinkProgram

        subroutine glGetProgramiv(program, pname, params) bind(c, name='glGetProgramiv')
            import :: GLuint, GLenum, c_ptr
            integer(GLuint), value :: program
            integer(GLenum), value :: pname
            type(c_ptr), value :: params
        end subroutine glGetProgramiv

        subroutine glUseProgram(program) bind(c, name='glUseProgram')
            import :: GLuint
            integer(GLuint), value :: program
        end subroutine glUseProgram

        subroutine glDeleteShader(shader) bind(c, name='glDeleteShader')
            import :: GLuint
            integer(GLuint), value :: shader
        end subroutine glDeleteShader

        function glGetUniformLocation(program, name) bind(c, name='glGetUniformLocation')
            import :: GLuint, GLint, c_char
            integer(GLuint), value :: program
            character(kind=c_char), dimension(*) :: name
            integer(GLint) :: glGetUniformLocation
        end function glGetUniformLocation

        subroutine glUniformMatrix4fv(location, count, transpose, value) bind(c, name='glUniformMatrix4fv')
            import :: GLint, GLsizei, GLboolean, c_ptr
            integer(GLint), value :: location
            integer(GLsizei), value :: count
            integer(GLboolean), value :: transpose
            type(c_ptr), value :: value
        end subroutine glUniformMatrix4fv

        subroutine glUniform3f(location, v0, v1, v2) bind(c, name='glUniform3f')
            import :: GLint, GLfloat
            integer(GLint), value :: location
            real(GLfloat), value :: v0, v1, v2
        end subroutine glUniform3f

        subroutine glUniform1i(location, v0) bind(c, name='glUniform1i')
            import :: GLint
            integer(GLint), value :: location, v0
        end subroutine glUniform1i

        ! Buffer functions
        subroutine glGenBuffers(n, buffers) bind(c, name='glGenBuffers')
            import :: GLsizei, c_ptr
            integer(GLsizei), value :: n
            type(c_ptr), value :: buffers
        end subroutine glGenBuffers

        subroutine glBindBuffer(target, buffer) bind(c, name='glBindBuffer')
            import :: GLenum, GLuint
            integer(GLenum), value :: target
            integer(GLuint), value :: buffer
        end subroutine glBindBuffer

        subroutine glBufferData(target, size, data, usage) bind(c, name='glBufferData')
            import :: GLenum, c_size_t, c_ptr
            integer(GLenum), value :: target
            integer(c_size_t), value :: size
            type(c_ptr), value :: data
            integer(GLenum), value :: usage
        end subroutine glBufferData

        subroutine glGenVertexArrays(n, arrays) bind(c, name='glGenVertexArrays')
            import :: GLsizei, c_ptr
            integer(GLsizei), value :: n
            type(c_ptr), value :: arrays
        end subroutine glGenVertexArrays

        subroutine glBindVertexArray(array) bind(c, name='glBindVertexArray')
            import :: GLuint
            integer(GLuint), value :: array
        end subroutine glBindVertexArray

        subroutine glVertexAttribPointer(index, size, type, normalized, stride, pointer) &
                                        bind(c, name='glVertexAttribPointer')
            import :: GLuint, GLint, GLenum, GLboolean, GLsizei, c_ptr
            integer(GLuint), value :: index
            integer(GLint), value :: size
            integer(GLenum), value :: type
            integer(GLboolean), value :: normalized
            integer(GLsizei), value :: stride
            type(c_ptr), value :: pointer
        end subroutine glVertexAttribPointer

        subroutine glEnableVertexAttribArray(index) bind(c, name='glEnableVertexAttribArray')
            import :: GLuint
            integer(GLuint), value :: index
        end subroutine glEnableVertexAttribArray

        ! Texture functions
        subroutine glGenTextures(n, textures) bind(c, name='glGenTextures')
            import :: GLsizei, c_ptr
            integer(GLsizei), value :: n
            type(c_ptr), value :: textures
        end subroutine glGenTextures

        subroutine glDeleteTextures(n, textures) bind(c, name='glDeleteTextures')
            import :: GLsizei, c_ptr
            integer(GLsizei), value :: n
            type(c_ptr), value :: textures
        end subroutine glDeleteTextures

        subroutine glActiveTexture(texture) bind(c, name='glActiveTexture')
            import :: GLenum
            integer(GLenum), value :: texture
        end subroutine glActiveTexture

        subroutine glBindTexture(target, texture) bind(c, name='glBindTexture')
            import :: GLenum, GLuint
            integer(GLenum), value :: target
            integer(GLuint), value :: texture
        end subroutine glBindTexture

        subroutine glTexImage2D(target, level, internal_format, width, height, border, &
                               format, type, data) bind(c, name='glTexImage2D')
            import :: GLenum, GLint, GLsizei, c_ptr
            integer(GLenum), value :: target
            integer(GLint), value :: level, internal_format, border
            integer(GLsizei), value :: width, height
            integer(GLenum), value :: format, type
            type(c_ptr), value :: data
        end subroutine glTexImage2D

        subroutine glTexParameteri(target, pname, param) bind(c, name='glTexParameteri')
            import :: GLenum, GLint
            integer(GLenum), value :: target, pname
            integer(GLint), value :: param
        end subroutine glTexParameteri

        ! Drawing
        subroutine glDrawArrays(mode, first, count) bind(c, name='glDrawArrays')
            import :: GLenum, GLint, GLsizei
            integer(GLenum), value :: mode
            integer(GLint), value :: first
            integer(GLsizei), value :: count
        end subroutine glDrawArrays

        subroutine glDrawArraysInstanced(mode, first, count, instancecount) &
                                        bind(c, name='glDrawArraysInstanced')
            import :: GLenum, GLint, GLsizei
            integer(GLenum), value :: mode
            integer(GLint), value :: first
            integer(GLsizei), value :: count, instancecount
        end subroutine glDrawArraysInstanced

    end interface

end module opengl_bindings
