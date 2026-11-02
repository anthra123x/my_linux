#version 300 es
precision highp float;

in vec2 v_texcoord;
layout(location = 0) out vec4 fragColor;

uniform sampler2D tex;

// Radio de difuminado óptimo para hacer ilegible cualquier texto o fondo
const float BLUR_RADIUS = 32.0;

void main() {
    vec2 texel = 1.0 / vec2(textureSize(tex, 0));
    vec4 color = vec4(0.0);
    float totalWeight = 0.0;

    // Muestra central
    color += texture(tex, v_texcoord) * 4.0;
    totalWeight += 4.0;

    // Muestreo concéntrico en espiral (4 anillos x 8 muestras = 32 muestras ponderadas)
    const int RINGS = 4;
    const int SAMPLES_PER_RING = 8;
    const float PI2 = 6.28318530718;

    for (int r = 1; r <= RINGS; r++) {
        float radius = (float(r) / float(RINGS)) * BLUR_RADIUS;
        float weight = float(RINGS - r + 1);
        float angleOffset = float(r) * 0.392699; // Offset para evitar artefactos visuales

        for (int i = 0; i < SAMPLES_PER_RING; i++) {
            float angle = angleOffset + (float(i) / float(SAMPLES_PER_RING)) * PI2;
            vec2 offset = vec2(cos(angle), sin(angle)) * radius * texel;
            color += texture(tex, v_texcoord + offset) * weight;
            totalWeight += weight;
        }
    }

    vec4 blurred = color / totalWeight;

    // Velo de privacidad elegante: atenuación suave del 15%
    blurred.rgb *= 0.85;

    fragColor = blurred;
}
