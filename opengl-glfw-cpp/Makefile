CXX ?= c++
CXXFLAGS ?= -std=c++26 -Wall -Wextra -Wpedantic
CXXFLAGS += -Wno-c23-extensions
CPPFLAGS += $(shell pkg-config --cflags glfw3 epoxy)
LDLIBS += $(shell pkg-config --libs glfw3 epoxy)

TARGET := glfw-window
SOURCES := main.cpp application.cpp shader.cpp
IMAGE_TEST_TARGET := image-test

.PHONY: all run run-image clean

all: $(TARGET) $(IMAGE_TEST_TARGET)

$(TARGET): $(SOURCES) vertex_shader.glsl fragment_shader.glsl fragment_shader2.glsl \
	  fragement_uniform_shader.glsl treemap_vertex_shader.glsl \
	  treemap_fragment_shader.glsl more_attributes_vertex_shader.glsl \
	  more_attributes_fragment_shader.glsl
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(SOURCES) -o $@ $(LDFLAGS) $(LDLIBS)

$(IMAGE_TEST_TARGET): image_test.cpp ppm.hpp stb_image.h
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) image_test.cpp -o $@ $(LDFLAGS)

run: $(TARGET)
	./$(TARGET)

run-image: $(IMAGE_TEST_TARGET)
	./$(IMAGE_TEST_TARGET)

clean:
	rm -f $(TARGET) $(IMAGE_TEST_TARGET)
