#include <metal_stdlib>
using namespace metal;

#define vec2 float2
#define vec3 float3
#define vec4 float4
#define ivec2 int2
#define ivec3 int3
#define ivec4 int4
#define mat2 float2x2
#define mat3 float3x3
#define mat4 float4x4

#define mod fmod
#define atan 6.28318530718-atan2

struct VertInOut {
    float4 pos[[position]];
};

struct FragmentShaderArguments {
    device float *time[[id(0)]];
    device float2 *resolution[[id(1)]];
    device float2 *mouse[[id(2)]];
    texture2d<float> o0[[id(3)]];
    texture2d<float> o1[[id(4)]];
    texture2d<float> o2[[id(5)]];
    texture2d<float> o3[[id(6)]];
    texture2d<float> s0[[id(7)]];
    texture2d<float> s1[[id(8)]];
    texture2d<float> s2[[id(9)]];
    texture2d<float> s3[[id(10)]];
};

vertex VertInOut vertexShader(constant float4 *pos[[buffer(0)]],uint vid[[vertex_id]]) {
    VertInOut outVert;
    outVert.pos = pos[vid];
    return outVert;
}

// Reference: http://glslsandbox.com/e#36694.0
fragment float4 fragmentShader(VertInOut inFrag[[stage_in]],constant FragmentShaderArguments &args[[buffer(0)]]) {
    
    float time = args.time[0];
    float2 resolution = args.resolution[0];
    float2 mouse = args.mouse[0];
    
    float2 gl_FragCoord = inFrag.pos.xy;
        
    vec2 position = ( gl_FragCoord.xy / resolution.xy );

    float color = 0.0;	
    float vx, vy, vz, vxr;
    float dx, llx, dy, lly, dz, llz;
    int px, py, pz, ccc, P;
    float k, k2;
    ivec4 di;
    vec4 X;
    vec4 d=vec4(time,mouse.y*3.0,.0,.0);
    vx=(position.x-1.0)+0.0001;
    vy=(position.y -1.0)+0.0001;
    vz=0.5+.0001;
    vxr=(vx*cos(mouse.x*2.5)+vz*sin(mouse.x*2.5));
    vz=(-vx*sin(mouse.x*2.5)+vz*cos(mouse.x*2.5));
    vx=vxr;
    X=fract(d);
    dx = 1000.0/vx; dy = 1000.0/vy; dz = 1000.0/vz;
    px=1; llx=dx*(1.0-X[0]);
    py=16; lly=dy*(1.0-X[1]);
    pz=256; llz=dz*(1.0-X[2]);
    if (dx<.0) {px=-1; dx=-dx; llx=dx*X[0];}
    if (dy<.0) {py=-16; dy=-dy; lly=dy*X[1];}
    if (dz<.0) {pz=-256; dz=-dz; llz=dz*X[2];}
    ccc=0;
    di=ivec4(d[0],d[1],d[2],d[3]);
    P=di[2]*256+di[1]*16+di[0];
    color=1.0;
    for (int i=0; i<40; i++)
    {
        if ((llx<=lly) && (llx<=llz))
        {
            P+=px; llx+=dx; k=0.75;
        }
        else
        {
            if (lly<=llz)
            {
                P+=py; lly+=dy; k=0.9;
            }
            else
            {
                P+=pz; llz+=dz; k=1.0;
            }
        }
        if ((fract(float(P)/29.0)<.01)&&(color==1.0)) {
            color=float(i)/40.0;
            k2=k;
        }
    }
    
    return float4(k2*(1.0-color),k2*(1.0-color),k2*k2*(1.0-color),1.0 );
}