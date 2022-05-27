@ctype vec2 @import("../math.zig").Vec2

@vs vs
uniform vs_params {
    vec2 disp_size;
};

in vec2 position;
in vec2 texcoord0;
in vec4 color0;

out vec2 uv;
out vec4 color;

void main() {
    gl_Position = vec4(((position/disp_size)-0.5)*vec2(2.0,-2.0), 0.5, 1.0);
    uv = texcoord0;
    color = color0;
}
@end

@fs fs
uniform sampler2D tex;

in vec2 uv;
in vec4 color;
out vec4 frag_color;

void main() {
    frag_color = texture(tex, uv) * color;
}
@end

@program snuk vs fs