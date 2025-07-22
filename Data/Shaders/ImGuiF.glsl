#version 330 core

in vec2 TexCoord;
in vec4  Color;

uniform sampler2D Texture;

out vec4 outColor;

void main()
{
	outColor = Color;
}