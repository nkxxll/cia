#pragma once

#include <epoxy/gl.h>
#include <string>

struct Shader {
  unsigned int ID;
};

namespace shader {
void use(const Shader &shader);
void init(Shader &shader, const char *vertexPath, const char *fragmentPath);
void setBool(const Shader &shader, const std::string &name, bool value);
void setInt(const Shader &shader, const std::string &name, int value);
void setFloat(const Shader &shader, const std::string &name, float value);
} // namespace shader
