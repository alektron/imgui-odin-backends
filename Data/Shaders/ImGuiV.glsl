#version 330 core

layout(location = 0) in vec2 position;
layout(location = 1) in vec2 texCoord;
layout(location = 2) in uvec4 color;

uniform vec2 u_ViewportSize;

out vec2 TexCoord;
out vec4  Color;

void main()
{
	TexCoord = texCoord;
	Color = vec4(color) / 255;

  vec2 pos = ((position.xy) / u_ViewportSize) * 2 - 1;
  pos.y *= -1;
  gl_Position = vec4(pos, 0.0, 1.0);
}