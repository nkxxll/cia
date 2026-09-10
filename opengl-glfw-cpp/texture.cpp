#include "texture.hpp"

#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

Texture::Texture(const char *filename) {
	data = stbi_load(filename, &width, &height, &n, 0);
	if (data == nullptr) {
		const char *reason = stbi_failure_reason();
		throw std::runtime_error(std::string("Failed to load texture '") + filename +
		                         "': " + (reason != nullptr ? reason : "unknown error"));
	}
}

Texture::~Texture() {
	stbi_image_free(data);
}
