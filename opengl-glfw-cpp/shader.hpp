#pragma once

#include <epoxy/gl.h>
#include <string>
#include <string_view>

struct Shader {
  GLuint ID = 0;
};

namespace shader {
void use(const Shader &shader);
bool init(Shader &shader, const char *vertexPath, const char *fragmentPath);
bool initSource(Shader &shader, std::string_view vertexSource,
                std::string_view fragmentSource);
void deinit(Shader &shader);
void setBool(const Shader &shader, const std::string &name, bool value);
void setInt(const Shader &shader, const std::string &name, int value);
void setFloat(const Shader &shader, const std::string &name, float value);
} // namespace shader
