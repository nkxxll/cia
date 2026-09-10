#ifndef PPM_HPP
#define PPM_HPP

#include <cstddef>
#include <limits>
#include <ostream>
#include <stdexcept>
#include <vector>

namespace ppm {

// Write an 8-bit image buffer as a binary PPM (P6) image.
inline void write(std::ostream &output, const unsigned char *pixels, int width,
                  int height, int channels) {
  if (pixels == nullptr) {
    throw std::invalid_argument("ppm: pixels must not be null");
  }
  if (width <= 0 || height <= 0) {
    throw std::invalid_argument("ppm: dimensions must be positive");
  }
  if (channels < 1 || channels > 4) {
    throw std::invalid_argument("ppm: expected one to four channels");
  }

  const auto image_width = static_cast<std::size_t>(width);
  const auto image_height = static_cast<std::size_t>(height);
  if (image_height > std::numeric_limits<std::size_t>::max() / image_width) {
    throw std::overflow_error("ppm: image is too large");
  }

  const std::size_t pixel_count = image_width * image_height;
  if (pixel_count > std::numeric_limits<std::size_t>::max() / 3) {
    throw std::overflow_error("ppm: image is too large");
  }

  output << "P6\n" << width << ' ' << height << "\n255\n";

  if (channels == 3) {
    output.write(reinterpret_cast<const char *>(pixels),
                 static_cast<std::streamsize>(pixel_count * 3));
  } else {
    std::vector<unsigned char> rgb(pixel_count * 3);
    for (std::size_t i = 0; i < pixel_count; ++i) {
      if (channels < 3) {
        rgb[i * 3] = pixels[i * static_cast<std::size_t>(channels)];
        rgb[i * 3 + 1] = rgb[i * 3];
        rgb[i * 3 + 2] = rgb[i * 3];
      } else {
        rgb[i * 3] = pixels[i * 4];
        rgb[i * 3 + 1] = pixels[i * 4 + 1];
        rgb[i * 3 + 2] = pixels[i * 4 + 2];
      }
    }
    output.write(reinterpret_cast<const char *>(rgb.data()),
                 static_cast<std::streamsize>(rgb.size()));
  }

  if (!output) {
    throw std::runtime_error("ppm: failed to write image");
  }
}

} // namespace ppm

#endif
