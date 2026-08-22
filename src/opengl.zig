const c = @cImport({
    @cInclude("epoxy/gl.h");
});

pub const GLenum = c.GLenum;
pub const GLuint = c.GLuint;
pub const GLint = c.GLint;
pub const GLsizei = c.GLsizei;
pub const GLfloat = c.GLfloat;
pub const GLchar = c.GLchar;

pub const FALSE: GLint = 0;
pub const COLOR_BUFFER_BIT: GLenum = 0x00004000;
pub const TRIANGLES: GLenum = 0x0004;
pub const VIEWPORT: GLenum = 0x0BA2;
pub const VERTEX_SHADER: GLenum = 0x8B31;
pub const FRAGMENT_SHADER: GLenum = 0x8B30;
pub const COMPILE_STATUS: GLenum = 0x8B81;
pub const LINK_STATUS: GLenum = 0x8B82;
pub const INFO_LOG_LENGTH: GLenum = 0x8B84;

pub const glAttachShader = c.glAttachShader;
pub const glBindVertexArray = c.glBindVertexArray;
pub const glClear = c.glClear;
pub const glClearColor = c.glClearColor;
pub const glCompileShader = c.glCompileShader;
pub const glCreateProgram = c.glCreateProgram;
pub const glCreateShader = c.glCreateShader;
pub const glDeleteProgram = c.glDeleteProgram;
pub const glDeleteShader = c.glDeleteShader;
pub const glDeleteVertexArrays = c.glDeleteVertexArrays;
pub const glDrawArrays = c.glDrawArrays;
pub const glGenVertexArrays = c.glGenVertexArrays;
pub const glGetIntegerv = c.glGetIntegerv;
pub const glGetProgramInfoLog = c.glGetProgramInfoLog;
pub const glGetProgramiv = c.glGetProgramiv;
pub const glGetShaderInfoLog = c.glGetShaderInfoLog;
pub const glGetShaderiv = c.glGetShaderiv;
pub const glGetUniformLocation = c.glGetUniformLocation;
pub const glLinkProgram = c.glLinkProgram;
pub const glShaderSource = c.glShaderSource;
pub const glUniform1f = c.glUniform1f;
pub const glUniform2f = c.glUniform2f;
pub const glUseProgram = c.glUseProgram;
