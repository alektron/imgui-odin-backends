cbuffer ConstBuffer : register(b0)
{
  float2 ViewportSize;
}

struct vertexdata
{
  float2 position : POS;
  float2 tex      : TEX;
  uint   color    : COL;
};

struct pixeldata
{
  float4 position : SV_POSITION;
  float2 tex   : TEX;
  float4 color : COL;
};

Texture2D    mytexture : register(t0);
SamplerState mysampler : register(s0);

pixeldata vertex_shader(vertexdata vertex)
{
  pixeldata output;
  output.position = float4((vertex.position / ViewportSize * 2 - 1) * float2(1, -1), 0, 1);
  output.tex = vertex.tex;
  output.color.x = float((vertex.color >>  0) & 0xFF) / 255;
  output.color.y = float((vertex.color >>  8) & 0xFF) / 255;
  output.color.z = float((vertex.color >> 16) & 0xFF) / 255;
  output.color.w = float((vertex.color >> 24) & 0xFF) / 255;
  return output;
}

float4 pixel_shader(pixeldata pixel) : SV_TARGET
{
  return float4(mytexture.Sample(mysampler, pixel.tex).xyzw) * pixel.color;
}