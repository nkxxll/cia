CXX ?= c++
CXXFLAGS ?= -std=c++26 -Wall -Wextra -Wpedantic
CXXFLAGS += -Wno-c23-extensions
CPPFLAGS += $(shell pkg-config --cflags glfw3 epoxy)
LDLIBS += $(shell pkg-config --libs glfw3 epoxy)

TARGET := glfw-window
SOURCES := main.cpp

.PHONY: all run clean

all: $(TARGET)

$(TARGET): $(SOURCES) vertex_shader.glsl fragment_shader.glsl fragment_shader2.glsl \
	  treemap_vertex_shader.glsl treemap_fragment_shader.glsl
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(SOURCES) -o $@ $(LDFLAGS) $(LDLIBS)

run: $(TARGET)
	./$(TARGET)

clean:
	rm -f $(TARGET)
