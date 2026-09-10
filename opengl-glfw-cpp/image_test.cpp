#include <fstream>
#include <iostream>
#define STB_IMAGE_IMPLEMENTATION
#include "ppm.hpp"
#include "stb_image.h"

int main(int argc, char **argv) {
  const char *path = argc > 1 ? argv[1] : "figher.jpeg";
  const char *output_path = argc > 2 ? argv[2] : "image.ppm";
  int x, y, n;
  unsigned char *data = stbi_load(path, &x, &y, &n, 0);
  if (data == nullptr) {
    std::cerr << "Error while reading image: " << stbi_failure_reason() << '\n';
    return 1;
  }

  try {
    std::ofstream output(output_path, std::ios::binary);
    if (!output) {
      throw std::runtime_error("Unable to open output file");
    }
    ppm::write(output, data, x, y, n);
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    stbi_image_free(data);
    return 1;
  }

  stbi_image_free(data);
  return 0;
}
