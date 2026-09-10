#include "application.hpp"

#include "shader.hpp"

#include <epoxy/gl.h>

#include <GLFW/glfw3.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <iterator>
#include <limits>
#include <memory>
#include <span>
#include <string_view>
#include <vector>

namespace {

const char vertexShaderSource[] = {
#embed "./vertex_shader.glsl"
};
const char fragmentShaderSource[] = {
#embed "./fragment_shader.glsl"
};
const char fragmentShaderSource2[] = {
#embed "./fragment_shader2.glsl"
};
const char uniformFragmentShaderSource[] = {
#embed "./fragement_uniform_shader.glsl"
};
const char treemapVertexShaderSource[] = {
#embed "./treemap_vertex_shader.glsl"
};
const char treemapFragmentShaderSource[] = {
#embed "./treemap_fragment_shader.glsl"
};
const char attributesVertexShaderSource[] = {
#embed "./more_attributes_vertex_shader.glsl"
};
const char attributesFragmentShaderSource[] = {
#embed "./more_attributes_fragment_shader.glsl"
};

template <std::size_t N> std::string_view source(const char (&bytes)[N]) {
  return {bytes, N};
}

struct FileInfo {
  int size;
  std::string_view name;
};

struct Rectangle {
  float x, y;
  float width, height;
};

struct Color {
  int r, g, b, a;
};

constexpr FileInfo files[] = {
    {11752, "../treemapstudy"},
    {476384, "../.zig-cache"},
    {56, "../docs"},
    {8016, "../zig-out"},
    {776, "../.jj"},
    {1024, "../.git"},
    {72, "../src"},
    {498128, ".."},
};

constexpr Color colors[] = {
    {55, 126, 184, 255},  {77, 175, 74, 255}, {255, 127, 0, 255},
    {152, 78, 163, 255},  {228, 26, 28, 255}, {166, 86, 40, 255},
    {247, 129, 191, 255},
};

struct Mesh {
  GLuint vertexArray = 0;
  GLuint vertexBuffer = 0;
  GLsizei vertexCount = 0;
};

struct TreemapVertex {
  float x, y;
  float r, g, b, a;
};

struct State {
  std::array<Mesh, 2> meshes;
  std::array<Shader, 2> shaders;
  std::vector<FileInfo> entries;
  GLint viewportLocation = -1;
  int layoutWidth = -1;
  int layoutHeight = -1;
};

void destroyState(void *opaque) {
  const auto state = static_cast<State *>(opaque);
  for (auto &mesh : state->meshes) {
    glDeleteVertexArrays(1, &mesh.vertexArray);
    glDeleteBuffers(1, &mesh.vertexBuffer);
  }
  for (auto &program : state->shaders) {
    shader::deinit(program);
  }
  delete state;
}

template <std::size_t N>
void initPositionMesh(Mesh &mesh, const float (&vertices)[N]) {
  glGenVertexArrays(1, &mesh.vertexArray);
  glGenBuffers(1, &mesh.vertexBuffer);
  glBindVertexArray(mesh.vertexArray);
  glBindBuffer(GL_ARRAY_BUFFER, mesh.vertexBuffer);
  glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);
  glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 3 * sizeof(float), nullptr);
  glEnableVertexAttribArray(0);
  glBindVertexArray(0);
  mesh.vertexCount = static_cast<GLsizei>(N / 3);
}

template <std::size_t N>
void initColorMesh(Mesh &mesh, const float (&vertices)[N]) {
  glGenVertexArrays(1, &mesh.vertexArray);
  glGenBuffers(1, &mesh.vertexBuffer);
  glBindVertexArray(mesh.vertexArray);
  glBindBuffer(GL_ARRAY_BUFFER, mesh.vertexBuffer);
  glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);
  glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 6 * sizeof(float), nullptr);
  glEnableVertexAttribArray(0);
  glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, 6 * sizeof(float),
                        reinterpret_cast<void *>(3 * sizeof(float)));
  glEnableVertexAttribArray(1);
  glBindVertexArray(0);
  mesh.vertexCount = static_cast<GLsizei>(N / 6);
}

void drawMesh(const Mesh &mesh, const Shader &program) {
  shader::use(program);
  glBindVertexArray(mesh.vertexArray);
  glDrawArrays(GL_TRIANGLES, 0, mesh.vertexCount);
}

bool initRectangle(State &state) {
  if (!shader::initSource(state.shaders[0], source(vertexShaderSource),
                          source(fragmentShaderSource))) {
    return false;
  }
  constexpr float vertices[] = {
      -0.5F, -0.5F, 0.0F, 0.5F, -0.5F, 0.0F, 0.5F,  0.5F, 0.0F,
      -0.5F, -0.5F, 0.0F, 0.5F, 0.5F,  0.0F, -0.5F, 0.5F, 0.0F,
  };
  initPositionMesh(state.meshes[0], vertices);
  return true;
}

bool initTriangles(State &state) {
  if (!shader::initSource(state.shaders[0], source(vertexShaderSource),
                          source(fragmentShaderSource)) ||
      !shader::initSource(state.shaders[1], source(vertexShaderSource),
                          source(fragmentShaderSource2))) {
    return false;
  }
  constexpr float first[] = {
      -0.5F, -0.5F, 0.0F, 0.5F, -0.5F, 0.0F, 0.5F, 0.5F, 0.0F,
  };
  constexpr float second[] = {
      -0.5F, -0.5F, 0.0F, 0.5F, 0.5F, 0.0F, -0.5F, 0.5F, 0.0F,
  };
  initPositionMesh(state.meshes[0], first);
  initPositionMesh(state.meshes[1], second);
  return true;
}

bool initUniformTriangle(State &state) {
  if (!shader::initSource(state.shaders[0], source(vertexShaderSource),
                          source(uniformFragmentShaderSource))) {
    return false;
  }
  constexpr float vertices[] = {
      -0.5F, -0.5F, 0.0F, 0.5F, -0.5F, 0.0F, 0.0F, 0.5F, 0.0F,
  };
  initPositionMesh(state.meshes[0], vertices);
  return true;
}

bool initMoreAttributes(State &state) {
  if (!shader::initSource(state.shaders[0],
                          source(attributesVertexShaderSource),
                          source(attributesFragmentShaderSource))) {
    return false;
  }
  constexpr float vertices[] = {
      -0.5F, 0.5F,  0.0F,  1.0F, 0.0F, 0.0F,  -0.5F, 0.0F,  0.0F,  0.0F,  0.0F,
      1.0F,  0.0F,  0.0F,  0.0F, 1.0F, 1.0F,  0.0F,  -0.5F, 0.5F,  0.0F,  1.0F,
      0.0F,  0.0F,  0.0F,  0.0F, 0.0F, 1.0F,  1.0F,  0.0F,  0.0F,  0.5F,  0.0F,
      0.0F,  1.0F,  0.0F,  0.0F, 0.5F, 0.0F,  1.0F,  0.0F,  0.0F,  0.0F,  0.0F,
      0.0F,  0.0F,  0.0F,  1.0F, 0.5F, 0.0F,  0.0F,  1.0F,  1.0F,  0.0F,  0.0F,
      0.5F,  0.0F,  1.0F,  0.0F, 0.0F, 0.5F,  0.0F,  0.0F,  1.0F,  1.0F,  0.0F,
      0.5F,  0.5F,  0.0F,  0.0F, 1.0F, 0.0F,  -0.5F, 0.0F,  0.0F,  1.0F,  0.0F,
      0.0F,  -0.5F, -0.5F, 0.0F, 0.0F, 0.0F,  1.0F,  0.0F,  -0.5F, 0.0F,  1.0F,
      1.0F,  0.0F,  -0.5F, 0.0F, 0.0F, 1.0F,  0.0F,  0.0F,  0.0F,  -0.5F, 0.0F,
      1.0F,  1.0F,  0.0F,  0.0F, 0.0F, 0.0F,  0.0F,  1.0F,  0.0F,  0.0F,  0.0F,
      0.0F,  1.0F,  0.0F,  0.0F, 0.0F, -0.5F, 0.0F,  0.0F,  0.0F,  1.0F,  0.5F,
      -0.5F, 0.0F,  1.0F,  1.0F, 0.0F, 0.0F,  0.0F,  0.0F,  1.0F,  0.0F,  0.0F,
      0.5F,  -0.5F, 0.0F,  1.0F, 1.0F, 0.0F,  0.5F,  0.0F,  0.0F,  0.0F,  1.0F,
      0.0F,
  };
  initColorMesh(state.meshes[0], vertices);
  return true;
}

bool initTreemap(State &state) {
  if (!shader::initSource(state.shaders[0], source(treemapVertexShaderSource),
                          source(treemapFragmentShaderSource))) {
    return false;
  }

  state.entries.assign(std::begin(files), std::end(files) - 1);
  state.viewportLocation =
      glGetUniformLocation(state.shaders[0].ID, "viewport");
  auto &mesh = state.meshes[0];
  glGenVertexArrays(1, &mesh.vertexArray);
  glGenBuffers(1, &mesh.vertexBuffer);
  glBindVertexArray(mesh.vertexArray);
  glBindBuffer(GL_ARRAY_BUFFER, mesh.vertexBuffer);
  glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, sizeof(TreemapVertex),
                        nullptr);
  glEnableVertexAttribArray(0);
  glVertexAttribPointer(1, 4, GL_FLOAT, GL_FALSE, sizeof(TreemapVertex),
                        reinterpret_cast<void *>(offsetof(TreemapVertex, r)));
  glEnableVertexAttribArray(1);
  glBindVertexArray(0);
  return true;
}

std::vector<Rectangle> treemapLayout(const std::vector<FileInfo> &entries,
                                     int width, int height) {
  std::vector<Rectangle> rectangles;
  rectangles.reserve(entries.size());

  const auto sumSizes = [](std::span<const FileInfo> group) {
    std::int64_t total = 0;
    for (const auto &entry : group) {
      total += entry.size;
    }
    return total;
  };

  const auto splitRegions = [](Rectangle area, std::int64_t firstSize,
                               std::int64_t pivotSize, std::int64_t secondSize,
                               std::int64_t thirdSize) {
    const float total =
        static_cast<float>(firstSize + pivotSize + secondSize + thirdSize);
    std::array<Rectangle, 4> regions;
    if (area.width >= area.height) {
      const float firstWidth = area.width * firstSize / total;
      const float middleWidth = area.width * (pivotSize + secondSize) / total;
      const float pivotHeight =
          area.height * pivotSize / (pivotSize + secondSize);
      regions[0] = {area.x, area.y, firstWidth, area.height};
      regions[1] = {area.x + firstWidth, area.y, middleWidth, pivotHeight};
      regions[2] = {area.x + firstWidth, area.y + pivotHeight, middleWidth,
                    area.height - pivotHeight};
      regions[3] = {area.x + firstWidth + middleWidth, area.y,
                    area.width - firstWidth - middleWidth, area.height};
    } else {
      const float firstHeight = area.height * firstSize / total;
      const float middleHeight = area.height * (pivotSize + secondSize) / total;
      const float pivotWidth =
          area.width * pivotSize / (pivotSize + secondSize);
      regions[0] = {area.x, area.y, area.width, firstHeight};
      regions[1] = {area.x, area.y + firstHeight, pivotWidth, middleHeight};
      regions[2] = {area.x + pivotWidth, area.y + firstHeight,
                    area.width - pivotWidth, middleHeight};
      regions[3] = {area.x, area.y + firstHeight + middleHeight, area.width,
                    area.height - firstHeight - middleHeight};
    }
    return regions;
  };

  auto partition = [&](this auto &&partition, std::span<const FileInfo> group,
                       Rectangle area) -> void {
    if (group.empty()) {
      return;
    }
    if (group.size() == 1) {
      rectangles.push_back(area);
      return;
    }
    if (group.size() == 2) {
      const float ratio = static_cast<float>(group[0].size) / sumSizes(group);
      if (area.width >= area.height) {
        const float firstWidth = area.width * ratio;
        rectangles.push_back({area.x, area.y, firstWidth, area.height});
        rectangles.push_back({area.x + firstWidth, area.y,
                              area.width - firstWidth, area.height});
      } else {
        const float firstHeight = area.height * ratio;
        rectangles.push_back({area.x, area.y, area.width, firstHeight});
        rectangles.push_back({area.x, area.y + firstHeight, area.width,
                              area.height - firstHeight});
      }
      return;
    }

    std::size_t pivotIndex = 0;
    for (std::size_t i = 1; i < group.size(); ++i) {
      if (group[i].size > group[pivotIndex].size) {
        pivotIndex = i;
      }
    }
    const auto firstGroup = group.first(pivotIndex);
    const auto following = group.subspan(pivotIndex + 1);
    const std::int64_t firstSize = sumSizes(firstGroup);
    const std::int64_t pivotSize = group[pivotIndex].size;
    float bestAspectRatio = std::numeric_limits<float>::infinity();
    std::size_t bestSplit = 0;
    std::array<Rectangle, 4> bestRegions{};

    const auto considerSplit = [&](std::size_t splitAt) {
      const auto regions = splitRegions(area, firstSize, pivotSize,
                                        sumSizes(following.first(splitAt)),
                                        sumSizes(following.subspan(splitAt)));
      const auto &pivot = regions[1];
      float ratio = std::numeric_limits<float>::infinity();
      if (pivot.width > 0.0F && pivot.height > 0.0F) {
        ratio =
            std::max(pivot.width / pivot.height, pivot.height / pivot.width);
      }
      if (ratio < bestAspectRatio) {
        bestAspectRatio = ratio;
        bestSplit = splitAt;
        bestRegions = regions;
      }
    };

    if (following.size() <= 2) {
      considerSplit(following.size());
    } else {
      for (std::size_t splitAt = 1; splitAt + 1 < following.size(); ++splitAt) {
        considerSplit(splitAt);
      }
      considerSplit(following.size());
    }
    rectangles.push_back(bestRegions[1]);
    partition(firstGroup, bestRegions[0]);
    partition(following.first(bestSplit), bestRegions[2]);
    partition(following.subspan(bestSplit), bestRegions[3]);
  };

  partition(entries, {0.0F, 0.0F, static_cast<float>(width),
                      static_cast<float>(height)});
  return rectangles;
}

void uploadTreemap(State &state, const std::vector<Rectangle> &rectangles) {
  std::vector<TreemapVertex> vertices;
  vertices.reserve(rectangles.size() * 6);
  for (std::size_t i = 0; i < rectangles.size(); ++i) {
    constexpr float padding = 2.0F;
    const auto &rectangle = rectangles[i];
    const float tileWidth = std::max(0.0F, rectangle.width - 2 * padding);
    const float tileHeight = std::max(0.0F, rectangle.height - 2 * padding);
    if (tileWidth == 0.0F || tileHeight == 0.0F) {
      continue;
    }
    const auto &color = colors[i % std::size(colors)];
    const float r = color.r / 255.0F;
    const float g = color.g / 255.0F;
    const float b = color.b / 255.0F;
    const float a = color.a / 255.0F;
    const float left = rectangle.x + padding;
    const float top = rectangle.y + padding;
    const float right = left + tileWidth;
    const float bottom = top + tileHeight;
    vertices.insert(vertices.end(), {
                                        {left, top, r, g, b, a},
                                        {right, top, r, g, b, a},
                                        {right, bottom, r, g, b, a},
                                        {left, top, r, g, b, a},
                                        {right, bottom, r, g, b, a},
                                        {left, bottom, r, g, b, a},
                                    });
  }
  auto &mesh = state.meshes[0];
  glBindBuffer(GL_ARRAY_BUFFER, mesh.vertexBuffer);
  glBufferData(GL_ARRAY_BUFFER,
               static_cast<GLsizeiptr>(vertices.size() * sizeof(TreemapVertex)),
               vertices.data(), GL_DYNAMIC_DRAW);
  mesh.vertexCount = static_cast<GLsizei>(vertices.size());
}

void drawSingleMesh(void *opaque, int, int) {
  auto &state = *static_cast<State *>(opaque);
  drawMesh(state.meshes[0], state.shaders[0]);
}

void drawTriangles(void *opaque, int, int) {
  auto &state = *static_cast<State *>(opaque);
  drawMesh(state.meshes[0], state.shaders[0]);
  drawMesh(state.meshes[1], state.shaders[1]);
}

void drawUniformTriangle(void *opaque, int, int) {
  auto &state = *static_cast<State *>(opaque);
  shader::use(state.shaders[0]);
  const float green = std::sin(static_cast<float>(glfwGetTime())) / 2.0F + 0.5F;
  glUniform4f(glGetUniformLocation(state.shaders[0].ID, "ourColor"), 0.0F,
              green, 0.0F, 1.0F);
  glBindVertexArray(state.meshes[0].vertexArray);
  glDrawArrays(GL_TRIANGLES, 0, state.meshes[0].vertexCount);
}

void drawTreemap(void *opaque, int width, int height) {
  auto &state = *static_cast<State *>(opaque);
  if (width <= 0 || height <= 0) {
    return;
  }
  if (width != state.layoutWidth || height != state.layoutHeight) {
    uploadTreemap(state, treemapLayout(state.entries, width, height));
    state.layoutWidth = width;
    state.layoutHeight = height;
  }
  shader::use(state.shaders[0]);
  glBindVertexArray(state.meshes[0].vertexArray);
  glUniform2f(state.viewportLocation, static_cast<float>(width),
              static_cast<float>(height));
  glDrawArrays(GL_TRIANGLES, 0, state.meshes[0].vertexCount);
}

} // namespace

bool application::parseMode(std::string_view argument, ApplicationMode &mode) {
  if (argument == "rectangle") {
    mode = ApplicationMode::rectangle;
  } else if (argument == "triangles") {
    mode = ApplicationMode::triangles;
  } else if (argument == "color_changing_triangle") {
    mode = ApplicationMode::color_changing_triangle;
  } else if (argument == "treemap") {
    mode = ApplicationMode::treemap;
  } else if (argument == "more_attributes") {
    mode = ApplicationMode::more_attributes;
  } else {
    return false;
  }
  return true;
}

std::string_view application::modeUsage() {
  return "<rectangle|triangles|color_changing_triangle|treemap|more_"
         "attributes>";
}

bool application::init(Application &app, ApplicationMode mode) {
  auto state = std::make_unique<State>();
  bool initialized = false;
  switch (mode) {
  case ApplicationMode::rectangle:
    initialized = initRectangle(*state);
    app.render = drawSingleMesh;
    break;
  case ApplicationMode::triangles:
    initialized = initTriangles(*state);
    app.render = drawTriangles;
    break;
  case ApplicationMode::color_changing_triangle:
    initialized = initUniformTriangle(*state);
    app.render = drawUniformTriangle;
    break;
  case ApplicationMode::treemap:
    initialized = initTreemap(*state);
    app.render = drawTreemap;
    break;
  case ApplicationMode::more_attributes:
    initialized = initMoreAttributes(*state);
    app.render = drawSingleMesh;
    break;
  }

  if (!initialized) {
    destroyState(state.release());
    app.render = nullptr;
    return false;
  }
  app.state = state.release();
  app.destroy = destroyState;
  return true;
}

void application::draw(Application &app, int width, int height) {
  app.render(app.state, width, height);
}

void application::deinit(Application &app) {
  if (app.destroy != nullptr) {
    app.destroy(app.state);
  }
  app = {};
}
