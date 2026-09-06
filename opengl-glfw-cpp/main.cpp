#include <epoxy/gl.h>

#define GLFW_INCLUDE_NONE
#include <GLFW/glfw3.h>

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <iterator>
#include <limits>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace {

struct FileInfo {
  int size;
  std::string name;
};

struct Color {
  int r, g, b, a;
};

struct CPURectangle {
  float x, y;
  float width, height;
};

const FileInfo files[] = {
    {11752, "../treemapstudy"},
    {476384, "../.zig-cache"},
    {56, "../docs"},
    {8016, "../zig-out"},
    {776, "../.jj"},
    {1024, "../.git"},
    {72, "../src"},
    {498128, ".."},
};

const Color colors[] = {Color(55, 126, 184, 255), Color(77, 175, 74, 255),
                        Color(255, 127, 0, 255),  Color(152, 78, 163, 255),
                        Color(228, 26, 28, 255),  Color(166, 86, 40, 255),
                        Color(247, 129, 191, 255)};

std::vector<CPURectangle>
treemap_layout(const std::vector<FileInfo> &entries, const int bounds[2]) {
  std::vector<FileInfo> positive_entries;
  positive_entries.reserve(entries.size());
  for (const auto &entry : entries) {
    if (entry.size > 0) {
      positive_entries.push_back(entry);
    }
  }

  std::vector<CPURectangle> rectangles;
  rectangles.reserve(positive_entries.size());

  const auto sum_sizes = [](std::span<const FileInfo> group) {
    std::int64_t total = 0;
    for (const auto &entry : group) {
      total += entry.size;
    }
    return total;
  };

  const auto split_regions = [](CPURectangle area, std::int64_t first_size,
                                std::int64_t pivot_size,
                                std::int64_t second_size,
                                std::int64_t third_size) {
    const float total = static_cast<float>(first_size + pivot_size +
                                           second_size + third_size);
    std::array<CPURectangle, 4> regions;

    if (area.width >= area.height) {
      const float first_width = area.width * first_size / total;
      const float middle_width =
          area.width * (pivot_size + second_size) / total;
      const float pivot_height =
          area.height * pivot_size / (pivot_size + second_size);

      regions[0] = {area.x, area.y, first_width, area.height};
      regions[1] = {area.x + first_width, area.y, middle_width, pivot_height};
      regions[2] = {area.x + first_width, area.y + pivot_height, middle_width,
                    area.height - pivot_height};
      regions[3] = {area.x + first_width + middle_width, area.y,
                    area.width - first_width - middle_width, area.height};
    } else {
      const float first_height = area.height * first_size / total;
      const float middle_height =
          area.height * (pivot_size + second_size) / total;
      const float pivot_width =
          area.width * pivot_size / (pivot_size + second_size);

      regions[0] = {area.x, area.y, area.width, first_height};
      regions[1] = {area.x, area.y + first_height, pivot_width, middle_height};
      regions[2] = {area.x + pivot_width, area.y + first_height,
                    area.width - pivot_width, middle_height};
      regions[3] = {area.x, area.y + first_height + middle_height, area.width,
                    area.height - first_height - middle_height};
    }

    return regions;
  };

  auto partition = [&](this auto &&partition, std::span<const FileInfo> group,
                       CPURectangle area) -> void {
    if (group.empty()) {
      return;
    }
    if (group.size() == 1) {
      rectangles.push_back(area);
      return;
    }
    if (group.size() == 2) {
      const float first_ratio = static_cast<float>(group[0].size) /
                                static_cast<float>(sum_sizes(group));
      if (area.width >= area.height) {
        const float first_width = area.width * first_ratio;
        rectangles.push_back({area.x, area.y, first_width, area.height});
        rectangles.push_back({area.x + first_width, area.y,
                              area.width - first_width, area.height});
      } else {
        const float first_height = area.height * first_ratio;
        rectangles.push_back({area.x, area.y, area.width, first_height});
        rectangles.push_back({area.x, area.y + first_height, area.width,
                              area.height - first_height});
      }
      return;
    }

    std::size_t pivot_index = 0;
    for (std::size_t i = 1; i < group.size(); ++i) {
      if (group[i].size > group[pivot_index].size) {
        pivot_index = i;
      }
    }

    const auto first_group = group.first(pivot_index);
    const auto following = group.subspan(pivot_index + 1);
    const std::int64_t first_size = sum_sizes(first_group);
    const std::int64_t pivot_size = group[pivot_index].size;

    float best_aspect_ratio = std::numeric_limits<float>::infinity();
    std::size_t best_split = 0;
    std::array<CPURectangle, 4> best_regions{};
    bool found_split = false;

    const auto consider_split = [&](std::size_t split_at) {
      const auto second_group = following.first(split_at);
      const auto third_group = following.subspan(split_at);
      const auto regions =
          split_regions(area, first_size, pivot_size, sum_sizes(second_group),
                        sum_sizes(third_group));
      const auto &pivot_region = regions[1];
      float aspect_ratio = std::numeric_limits<float>::infinity();
      if (pivot_region.width > 0.0F && pivot_region.height > 0.0F) {
        aspect_ratio =
            std::max(pivot_region.width / pivot_region.height,
                     pivot_region.height / pivot_region.width);
      }
      if (!found_split || aspect_ratio < best_aspect_ratio) {
        found_split = true;
        best_aspect_ratio = aspect_ratio;
        best_split = split_at;
        best_regions = regions;
      }
    };

    if (following.size() <= 2) {
      consider_split(following.size());
    } else {
      for (std::size_t split_at = 1; split_at + 1 < following.size();
           ++split_at) {
        consider_split(split_at);
      }
      consider_split(following.size());
    }

    rectangles.push_back(best_regions[1]);
    partition(first_group, best_regions[0]);
    partition(following.first(best_split), best_regions[2]);
    partition(following.subspan(best_split), best_regions[3]);
  };

  partition(std::span<const FileInfo>(positive_entries),
            {0.0F, 0.0F, static_cast<float>(bounds[0]),
             static_cast<float>(bounds[1])});
  return rectangles;
}

void glfw_error_callback(int error, const char *description) {
  std::cerr << "GLFW error " << error << ": " << description << '\n';
}

void framebuffer_size_callback(GLFWwindow *_, int width, int height) {
  glViewport(0, 0, width, height);
}

void processInput(GLFWwindow *window) {
  if (glfwGetKey(window, GLFW_KEY_ESCAPE) == GLFW_PRESS) {
    glfwSetWindowShouldClose(window, GLFW_TRUE);
  }
}

float hexToGLFloatColor(int hex) {
  if (hex <= 0 && hex < 256) {
    std::cerr << "Hex value not in byte range" << std::endl;
    exit(1);
  }
  return static_cast<float>(hex) / 255;
}

const char vertex_shader_bytes[] = {
#embed "./vertex_shader.glsl"
};

const char fragment_shader_bytes[] = {
#embed "./fragment_shader.glsl"
};

const char fragment_shader_bytes2[] = {
#embed "./fragment_shader2.glsl"
};

const char treemap_vertex_shader_bytes[] = {
#embed "./treemap_vertex_shader.glsl"
};

const char treemap_fragment_shader_bytes[] = {
#embed "./treemap_fragment_shader.glsl"
};

struct Triangle {
  GLuint vertex_array = 0;
  GLuint vertex_buffer = 0;
  GLuint shader_program = 0;
};

struct Rectangle {
  GLuint vertex_array = 0;
  GLuint vertex_buffer = 0;
  GLuint shader_program = 0;
};

struct TreemapVertex {
  float x, y;
  float r, g, b, a;
};

struct TreemapRenderer {
  GLuint vertex_array = 0;
  GLuint vertex_buffer = 0;
  GLuint shader_program = 0;
  GLint viewport_location = -1;
  GLsizei vertex_count = 0;
};

enum class RenderMode { rectangle, triangles, treemap };

bool parseRenderMode(std::string_view argument, RenderMode &mode) {
  if (argument == "rectangle") {
    mode = RenderMode::rectangle;
  } else if (argument == "triangles") {
    mode = RenderMode::triangles;
  } else if (argument == "treemap") {
    mode = RenderMode::treemap;
  } else {
    return false;
  }
  return true;
}

GLuint compileShader(GLenum type, const char *source, GLint source_length) {
  const GLuint shader = glCreateShader(type);
  glShaderSource(shader, 1, &source, &source_length);
  glCompileShader(shader);

  GLint success = GL_FALSE;
  glGetShaderiv(shader, GL_COMPILE_STATUS, &success);
  if (success == GL_TRUE) {
    return shader;
  }

  char info_log[512];
  glGetShaderInfoLog(shader, sizeof(info_log), nullptr, info_log);
  std::cerr << "Shader compilation failed:\n" << info_log << '\n';
  glDeleteShader(shader);
  return 0;
}

bool createTreemapRenderer(TreemapRenderer &renderer) {
  const GLuint vertex_shader =
      compileShader(GL_VERTEX_SHADER, treemap_vertex_shader_bytes,
                    static_cast<GLint>(sizeof(treemap_vertex_shader_bytes)));
  const GLuint fragment_shader =
      compileShader(GL_FRAGMENT_SHADER, treemap_fragment_shader_bytes,
                    static_cast<GLint>(sizeof(treemap_fragment_shader_bytes)));
  if (vertex_shader == 0 || fragment_shader == 0) {
    glDeleteShader(vertex_shader);
    glDeleteShader(fragment_shader);
    return false;
  }

  renderer.shader_program = glCreateProgram();
  glAttachShader(renderer.shader_program, vertex_shader);
  glAttachShader(renderer.shader_program, fragment_shader);
  glLinkProgram(renderer.shader_program);
  glDeleteShader(vertex_shader);
  glDeleteShader(fragment_shader);

  GLint success = GL_FALSE;
  glGetProgramiv(renderer.shader_program, GL_LINK_STATUS, &success);
  if (success != GL_TRUE) {
    char info_log[512];
    glGetProgramInfoLog(renderer.shader_program, sizeof(info_log), nullptr,
                        info_log);
    std::cerr << "Treemap shader program linking failed:\n"
              << info_log << '\n';
    glDeleteProgram(renderer.shader_program);
    renderer.shader_program = 0;
    return false;
  }

  renderer.viewport_location =
      glGetUniformLocation(renderer.shader_program, "viewport");

  glGenVertexArrays(1, &renderer.vertex_array);
  glGenBuffers(1, &renderer.vertex_buffer);
  glBindVertexArray(renderer.vertex_array);
  glBindBuffer(GL_ARRAY_BUFFER, renderer.vertex_buffer);
  glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, sizeof(TreemapVertex),
                        nullptr);
  glEnableVertexAttribArray(0);
  glVertexAttribPointer(
      1, 4, GL_FLOAT, GL_FALSE, sizeof(TreemapVertex),
      reinterpret_cast<void *>(offsetof(TreemapVertex, r)));
  glEnableVertexAttribArray(1);
  glBindVertexArray(0);
  return true;
}

void attachShader(Triangle *t, const GLuint vertex_shader,
                  const GLuint fragment_shader) {
  t->shader_program = glCreateProgram();
  glAttachShader(t->shader_program, vertex_shader);
  glAttachShader(t->shader_program, fragment_shader);
}

template <std::size_t N>
void arraysAndBuffers(Triangle *t, const float (&vertices)[N]) {
  glGenVertexArrays(1, &t->vertex_array);
  glGenBuffers(1, &t->vertex_buffer);
  glBindVertexArray(t->vertex_array);
  glBindBuffer(GL_ARRAY_BUFFER, t->vertex_buffer);
  glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);
  glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 3 * sizeof(float), nullptr);
  glEnableVertexAttribArray(0);
  glBindVertexArray(0);
}

bool createRectangle(Triangle triangles[2]) {
  const GLuint vertex_shader =
      compileShader(GL_VERTEX_SHADER, vertex_shader_bytes,
                    static_cast<GLint>(sizeof(vertex_shader_bytes)));
  const GLuint fragment_shader =
      compileShader(GL_FRAGMENT_SHADER, fragment_shader_bytes,
                    static_cast<GLint>(sizeof(fragment_shader_bytes)));

  const GLuint fragment_shader2 =
      compileShader(GL_FRAGMENT_SHADER, fragment_shader_bytes2,
                    static_cast<GLint>(sizeof(fragment_shader_bytes2)));

  if (vertex_shader == 0 || fragment_shader == 0 || fragment_shader2 == 0) {
    glDeleteShader(vertex_shader);
    glDeleteShader(fragment_shader);
    glDeleteShader(fragment_shader2);
    return false;
  }

  Triangle &a = triangles[0];
  Triangle &b = triangles[1];

  attachShader(&a, vertex_shader, fragment_shader);
  glLinkProgram(a.shader_program);
  attachShader(&b, vertex_shader, fragment_shader2);
  glLinkProgram(b.shader_program);

  glDeleteShader(vertex_shader);
  glDeleteShader(fragment_shader);
  glDeleteShader(fragment_shader2);

  const float va[] = {
      -0.5F, -0.5F, 0.0F, 0.5F, -0.5F, 0.0F, 0.5F, 0.5F, 0.0F,

  };
  const float vb[] = {
      -0.5F, -0.5F, 0.0F, 0.5F, 0.5F, 0.0F, -0.5F, 0.5F, 0.0F,
  };

  for (int i = 0; i < 2; ++i) {
    auto &t = triangles[i];
    GLint success = GL_FALSE;
    glGetProgramiv(t.shader_program, GL_LINK_STATUS, &success);
    if (success != GL_TRUE) {
      char info_log[512];
      glGetProgramInfoLog(t.shader_program, sizeof(info_log), nullptr,
                          info_log);
      std::cerr << "Shader program linking failed:\n" << info_log << '\n';
      glDeleteProgram(t.shader_program);
      t.shader_program = 0;
      return false;
    }
  }

  arraysAndBuffers(&triangles[0], va);
  arraysAndBuffers(&triangles[1], vb);
  return true;
}

bool createRectangle(Rectangle &rectangle) {
  const GLuint vertex_shader =
      compileShader(GL_VERTEX_SHADER, vertex_shader_bytes,
                    static_cast<GLint>(sizeof(vertex_shader_bytes)));
  const GLuint fragment_shader =
      compileShader(GL_FRAGMENT_SHADER, fragment_shader_bytes,
                    static_cast<GLint>(sizeof(fragment_shader_bytes)));
  if (vertex_shader == 0 || fragment_shader == 0) {
    glDeleteShader(vertex_shader);
    glDeleteShader(fragment_shader);
    return false;
  }

  rectangle.shader_program = glCreateProgram();
  glAttachShader(rectangle.shader_program, vertex_shader);
  glAttachShader(rectangle.shader_program, fragment_shader);
  glLinkProgram(rectangle.shader_program);
  glDeleteShader(vertex_shader);
  glDeleteShader(fragment_shader);

  GLint success = GL_FALSE;
  glGetProgramiv(rectangle.shader_program, GL_LINK_STATUS, &success);
  if (success != GL_TRUE) {
    char info_log[512];
    glGetProgramInfoLog(rectangle.shader_program, sizeof(info_log), nullptr,
                        info_log);
    std::cerr << "Shader program linking failed:\n" << info_log << '\n';
    glDeleteProgram(rectangle.shader_program);
    rectangle.shader_program = 0;
    return false;
  }

  const float vertices[] = {
      -0.5F, -0.5F, 0.0F, 0.5F, -0.5F, 0.0F, 0.5F,  0.5F, 0.0F,
      -0.5F, -0.5F, 0.0F, 0.5F, 0.5F,  0.0F, -0.5F, 0.5F, 0.0F,
  };

  glGenVertexArrays(1, &rectangle.vertex_array);
  glGenBuffers(1, &rectangle.vertex_buffer);
  glBindVertexArray(rectangle.vertex_array);
  glBindBuffer(GL_ARRAY_BUFFER, rectangle.vertex_buffer);
  glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);
  glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 3 * sizeof(float), nullptr);
  glEnableVertexAttribArray(0);
  glBindVertexArray(0);
  return true;
}

void cleanupObject(Triangle *t) {
  glDeleteVertexArrays(1, &t->vertex_array);
  glDeleteBuffers(1, &t->vertex_buffer);
  glDeleteProgram(t->shader_program);
}

void cleanupObject(Rectangle *r) {
  glDeleteVertexArrays(1, &r->vertex_array);
  glDeleteBuffers(1, &r->vertex_buffer);
  glDeleteProgram(r->shader_program);
}

void cleanupObject(TreemapRenderer *renderer) {
  glDeleteVertexArrays(1, &renderer->vertex_array);
  glDeleteBuffers(1, &renderer->vertex_buffer);
  glDeleteProgram(renderer->shader_program);
}

void drawRectangle(const Rectangle &rectangle) {
  glUseProgram(rectangle.shader_program);
  glBindVertexArray(rectangle.vertex_array);
  glDrawArrays(GL_TRIANGLES, 0, 6);
}

void drawTriangle(const Triangle &rectangle) {
  glUseProgram(rectangle.shader_program);
  glBindVertexArray(rectangle.vertex_array);
  glDrawArrays(GL_TRIANGLES, 0, 3);
}

void uploadTreemap(TreemapRenderer &renderer,
                   const std::vector<CPURectangle> &rectangles) {
  std::vector<TreemapVertex> vertices;
  vertices.reserve(rectangles.size() * 6);
  for (std::size_t i = 0; i < rectangles.size(); ++i) {
    const auto &rectangle = rectangles[i];
    const float padding = 2.0F;
    const float tile_width = std::max(0.0F, rectangle.width - 2 * padding);
    const float tile_height = std::max(0.0F, rectangle.height - 2 * padding);
    if (tile_width == 0.0F || tile_height == 0.0F) {
      continue;
    }

    const auto &color = colors[i % std::size(colors)];
    const float r = static_cast<float>(color.r) / 255.0F;
    const float g = static_cast<float>(color.g) / 255.0F;
    const float b = static_cast<float>(color.b) / 255.0F;
    const float a = static_cast<float>(color.a) / 255.0F;
    const float left = rectangle.x + padding;
    const float top = rectangle.y + padding;
    const float right = left + tile_width;
    const float bottom = top + tile_height;

    vertices.push_back({left, top, r, g, b, a});
    vertices.push_back({right, top, r, g, b, a});
    vertices.push_back({right, bottom, r, g, b, a});
    vertices.push_back({left, top, r, g, b, a});
    vertices.push_back({right, bottom, r, g, b, a});
    vertices.push_back({left, bottom, r, g, b, a});
  }

  glBindBuffer(GL_ARRAY_BUFFER, renderer.vertex_buffer);
  glBufferData(GL_ARRAY_BUFFER,
               static_cast<GLsizeiptr>(vertices.size() * sizeof(TreemapVertex)),
               vertices.data(), GL_DYNAMIC_DRAW);
  renderer.vertex_count = static_cast<GLsizei>(vertices.size());
}

void drawTreemap(const TreemapRenderer &renderer, int width, int height) {
  if (width <= 0 || height <= 0 || renderer.vertex_count == 0) {
    return;
  }

  glUseProgram(renderer.shader_program);
  glBindVertexArray(renderer.vertex_array);
  glUniform2f(renderer.viewport_location, static_cast<float>(width),
              static_cast<float>(height));
  glDrawArrays(GL_TRIANGLES, 0, renderer.vertex_count);
}

} // namespace

int main(int argc, char *argv[]) {
  RenderMode mode = RenderMode::rectangle;
  if (argc != 2 || !parseRenderMode(argv[1], mode)) {
    std::cerr << "Usage: " << argv[0]
              << " <rectangle|triangles|treemap>\n";
    return EXIT_FAILURE;
  }

  glfwSetErrorCallback(glfw_error_callback);

  if (glfwInit() != GLFW_TRUE) {
    return EXIT_FAILURE;
  }

  glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
  glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
  glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
#ifdef __APPLE__
  glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GLFW_TRUE);
#endif

  GLFWwindow *window =
      glfwCreateWindow(800, 600, "GLFW OpenGL Window", nullptr, nullptr);
  if (window == nullptr) {
    glfwTerminate();
    return EXIT_FAILURE;
  }

  glfwSetFramebufferSizeCallback(window, framebuffer_size_callback);
  glfwMakeContextCurrent(window);
  glfwSwapInterval(1);

  Rectangle rectangle;
  Triangle triangles[2];
  TreemapRenderer treemap_renderer;
  std::vector<FileInfo> treemap_entries;
  std::vector<CPURectangle> treemap_rectangles;
  int layout_width = -1;
  int layout_height = -1;

  bool initialized = false;
  switch (mode) {
  case RenderMode::rectangle:
    initialized = createRectangle(rectangle);
    break;
  case RenderMode::triangles:
    initialized = createRectangle(triangles);
    break;
  case RenderMode::treemap:
    treemap_entries.assign(files, files + std::size(files) - 1);
    initialized = createTreemapRenderer(treemap_renderer);
    break;
  }

  if (!initialized) {
    cleanupObject(&rectangle);
    cleanupObject(&triangles[0]);
    cleanupObject(&triangles[1]);
    cleanupObject(&treemap_renderer);
    glfwDestroyWindow(window);
    glfwTerminate();
    return EXIT_FAILURE;
  }

  while (glfwWindowShouldClose(window) == GLFW_FALSE) {
    processInput(window);

    // set buffer size
    int width = 0;
    int height = 0;
    glfwGetFramebufferSize(window, &width, &height);
    glViewport(0, 0, width, height);

    // clear the background with a color
    glClearColor(hexToGLFloatColor(0x1d), hexToGLFloatColor(20),
                 hexToGLFloatColor(21), 1.0F);
    glClear(GL_COLOR_BUFFER_BIT);

    switch (mode) {
    case RenderMode::rectangle:
      drawRectangle(rectangle);
      break;
    case RenderMode::triangles:
      drawTriangle(triangles[0]);
      drawTriangle(triangles[1]);
      break;
    case RenderMode::treemap:
      if (width != layout_width || height != layout_height) {
        const int bounds[] = {width, height};
        treemap_rectangles = treemap_layout(treemap_entries, bounds);
        uploadTreemap(treemap_renderer, treemap_rectangles);
        layout_width = width;
        layout_height = height;
      }
      drawTreemap(treemap_renderer, width, height);
      break;
    }

    glfwSwapBuffers(window);
    glfwPollEvents();
  }

  switch (mode) {
  case RenderMode::rectangle:
    cleanupObject(&rectangle);
    break;
  case RenderMode::triangles:
    cleanupObject(&triangles[0]);
    cleanupObject(&triangles[1]);
    break;
  case RenderMode::treemap:
    cleanupObject(&treemap_renderer);
    break;
  }
  glfwDestroyWindow(window);
  glfwTerminate();
  return EXIT_SUCCESS;
}
