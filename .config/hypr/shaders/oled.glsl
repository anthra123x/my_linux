#version 300 es
precision highp float;

in vec2 v_texcoord;
layout(location = 0) out vec4 fragColor;

uniform sampler2D tex;

// ==============================================================================
// Calibracion AMOLED / OLED para paneles IPS
// ==============================================================================
// 1. Saturacion global suave (colores naturales sin estridencias)
const float SATURATION = 1.10;

// 2. Viveza no lineal equilibrada
const float VIBRANCE = 0.26;

// 3. Contraste dinamico moderado (separacion limpia y suave)
const float CONTRAST = 1.12;

// 4. Corte de luz de fondo IPS (mantiene negros profundos sin aplastar detalles)
const float BLACK_FLOOR = 0.035;

// 5. Curva S organica suave para sombras tipo OLED
const float S_CURVE = 0.18;

// 6. Gamma compensado para maxima legibilidad
const float GAMMA = 1.05;

void main() {
    vec4 pixColor = texture(tex, v_texcoord);
    vec3 color = pixColor.rgb;

    // Luminancia Rec. 709
    float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));

    // --- Paso 1: Saturacion cinematica (gama amplia DCI-P3) ---
    color = mix(vec3(luma), color, SATURATION);

    // --- Paso 2: Vibrance selectivo ---
    float max_c = max(color.r, max(color.g, color.b));
    float min_c = min(color.r, min(color.g, color.b));
    float sat = max_c - min_c;
    float vib_amt = -VIBRANCE * sat + (1.0 + VIBRANCE);
    color = mix(vec3(luma), color, vib_amt);

    // --- Paso 3: Negros inky puros (recorta el glow del backlight de paneles IPS) ---
    color = max(vec3(0.0), color - BLACK_FLOOR) / (1.0 - BLACK_FLOOR);

    // Caida cuadratica en las sombras profundas (toe falloff para evitar posterizado)
    color = mix(color, color * color * (3.0 - 2.0 * color), S_CURVE);

    // --- Paso 4: Contraste dinámico ---
    color = ((color - 0.5) * CONTRAST) + 0.5;

    // --- Paso 5: Correccion Gamma ---
    color = pow(max(color, vec3(0.0)), vec3(1.0 / GAMMA));

    fragColor = vec4(clamp(color, 0.0, 1.0), pixColor.a);
}
