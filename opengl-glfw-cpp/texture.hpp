#include <stdexcept>
#include <string>

class Texture {
public:
	Texture(const char *filename);
	Texture(Texture &&) = default;
	Texture(const Texture &) = default;
	Texture &operator=(Texture &&) = default;
	Texture &operator=(const Texture &) = default;
	~Texture();
	unsigned int ID;
	int width, height, n;
	unsigned char* data;

private:
	
};

