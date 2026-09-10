#include "shader.hpp"

#include <fstream>
#include <iostream>
#include <iterator>
#include <string>
#include <string_view>

namespace {

GLuint compile(GLenum type, std::string_view source) {
  const GLuint object = glCreateShader(type);
  const char *bytes = source.data();
  const GLint length = static_cast<GLint>(source.size());
  glShaderSource(object, 1, &bytes, &length);
  glCompileShader(object);

  GLint success = GL_FALSE;
  glGetShaderiv(object, GL_COMPILE_STATUS, &success);
  if (success == GL_TRUE) {
    return object;
  }

  char infoLog[512];
  glGetShaderInfoLog(object, sizeof(infoLog), nullptr, infoLog);
  std::cerr << "Shader compilation failed:\n" << infoLog << '\n';
  glDeleteShader(object);
  return 0;
}

} // namespace

void shader::use(const Shader &shader) { glUseProgram(shader.ID); }

bool shader::init(Shader &shader, const char *vertexPath,
                  const char *fragmentPath) {
  std::ifstream vertexFile(vertexPath);
  std::ifstream fragmentFile(fragmentPath);
  if (!vertexFile || !fragmentFile) {
    std::cerr << "Could not read shader files: " << vertexPath << ", "
              << fragmentPath << '\n';
    return false;
  }

  const std::string vertexSource(std::istreambuf_iterator<char>(vertexFile),
                                 {});
  const std::string fragmentSource(std::istreambuf_iterator<char>(fragmentFile),
                                   {});
  return initSource(shader, vertexSource, fragmentSource);
}

bool shader::initSource(Shader &shader, std::string_view vertexSource,
                        std::string_view fragmentSource) {
  const GLuint vertex = compile(GL_VERTEX_SHADER, vertexSource);
  const GLuint fragment = compile(GL_FRAGMENT_SHADER, fragmentSource);
  if (vertex == 0 || fragment == 0) {
    glDeleteShader(vertex);
    glDeleteShader(fragment);
    return false;
  }

  shader.ID = glCreateProgram();
  glAttachShader(shader.ID, vertex);
  glAttachShader(shader.ID, fragment);
  glLinkProgram(shader.ID);
  glDeleteShader(vertex);
  glDeleteShader(fragment);

  GLint success = GL_FALSE;
  glGetProgramiv(shader.ID, GL_LINK_STATUS, &success);
  if (success == GL_TRUE) {
    return true;
  }

  char infoLog[512];
  glGetProgramInfoLog(shader.ID, sizeof(infoLog), nullptr, infoLog);
  std::cerr << "Shader program linking failed:\n" << infoLog << '\n';
  deinit(shader);
  return false;
}

void shader::deinit(Shader &shader) {
  glDeleteProgram(shader.ID);
  shader.ID = 0;
}

void shader::setFloat(const Shader &shader, const std::string &name,
                      float value) {
  glUniform1f(glGetUniformLocation(shader.ID, name.c_str()), value);
}

void shader::setInt(const Shader &shader, const std::string &name, int value) {
  glUniform1i(glGetUniformLocation(shader.ID, name.c_str()), value);
}

void shader::setBool(const Shader &shader, const std::string &name,
                     bool value) {
  glUniform1i(glGetUniformLocation(shader.ID, name.c_str()),
              static_cast<int>(value));
}
