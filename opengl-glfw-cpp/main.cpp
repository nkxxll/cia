#include "application.hpp"

#include <epoxy/gl.h>

#define GLFW_INCLUDE_NONE
#include <GLFW/glfw3.h>

#include <cstdlib>
#include <iostream>

namespace {

void glfwErrorCallback(int error, const char *description) {
  std::cerr << "GLFW error " << error << ": " << description << '\n';
}

void processInput(GLFWwindow *window) {
  //
  // quit on esc
  //
  if (glfwGetKey(window, GLFW_KEY_ESCAPE) == GLFW_PRESS) {
    glfwSetWindowShouldClose(window, GLFW_TRUE);
  }

  //
  // also quit on q
  //
  if (glfwGetKey(window, GLFW_KEY_Q) == GLFW_PRESS) {
    glfwSetWindowShouldClose(window, GLFW_TRUE);
  }
}

} // namespace

int main(int argc, char *argv[]) {
  ApplicationMode mode;
  if (argc != 2 || !application::parseMode(argv[1], mode)) {
    std::cerr << "Usage: " << argv[0] << " " << application::modeUsage()
              << '\n';
    return EXIT_FAILURE;
  }

  glfwSetErrorCallback(glfwErrorCallback);
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

  glfwMakeContextCurrent(window);
  glfwSwapInterval(1);

  Application app;
  if (!application::init(app, mode)) {
    glfwDestroyWindow(window);
    glfwTerminate();
    return EXIT_FAILURE;
  }

  while (glfwWindowShouldClose(window) == GLFW_FALSE) {
    processInput(window);

    int width = 0;
    int height = 0;
    glfwGetFramebufferSize(window, &width, &height);
    glViewport(0, 0, width, height);
    glClearColor(0x1d / 255.0F, 0x20 / 255.0F, 0x21 / 255.0F, 1.0F);
    glClear(GL_COLOR_BUFFER_BIT);

    application::draw(app, width, height);

    glfwSwapBuffers(window);
    glfwPollEvents();
  }

  application::deinit(app);
  glfwDestroyWindow(window);
  glfwTerminate();
  return EXIT_SUCCESS;
}
