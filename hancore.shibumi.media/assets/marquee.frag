#version 440
// Compile with Qt qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o marquee.frag.qsb marquee.frag
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 sourceScale;
    float scrollOffset;
};
layout(binding = 1) uniform sampler2D source;
layout(binding = 2) uniform sampler2D maskSource;
void main() {
    vec2 uv = qt_TexCoord0 * sourceScale + vec2(scrollOffset, 0.0);
    vec4 text = texture(source, uv);
    if (uv.x < 0.0 || uv.x > 1.0) text = vec4(0.0);
    // MultiEffect threshold/spread 0.5/0.5 maps to these smoothstep
    // edges: (threshold + 0.0001) * (1 + spread), minus spread + 0.0001.
    float fade = smoothstep(0.25005, 0.75015, texture(maskSource, qt_TexCoord0).a);
    fragColor = text * fade * qt_Opacity;
}
