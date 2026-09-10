#pragma once

#include <string_view>

enum class ApplicationMode {
  rectangle,
  triangles,
  color_changing_triangle,
  treemap,
  more_attributes,
};

struct Application {
  void *state = nullptr;
  void (*render)(void *, int, int) = nullptr;
  void (*destroy)(void *) = nullptr;
};

namespace application {

bool parseMode(std::string_view argument, ApplicationMode &mode);
std::string_view modeUsage();

bool init(Application &app, ApplicationMode mode);
void draw(Application &app, int width, int height);
void deinit(Application &app);

} // namespace application
