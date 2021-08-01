/*
PUT THIS ON A PLANE MESH
AND TAPE IT INFRONT OF YOUR PERSON'S CAMERA

or tape it onto somewhere else like a door frame or a picture...
just imagine having a lowrez game and then suddenly the game shows you this room with Ray Tracing XD 
just have an "RTX on" png overlay on the corner of the screen

otherwise you could try and convert this into a canvas 2D shader and stick it on the camera's viewport like that...
I wouldn't recommend you doing that actually
just wait for Godot 4 it would be way easier
*/




shader_type spatial;
render_mode unshaded,depth_draw_alpha_prepass,world_vertex_coords;

uniform bool active = true; // on/off switch for entire shader

uniform bool shadow = true; //enables shadows & directional lighting

uniform bool sun = false;
uniform float d_light_energy : hint_range(0, 16) = 1.0; //directional light energy
uniform vec3 d_light_dir = vec3(0.0,0.0,1.0); //directional light vector (global_transform.basis.z)... you don't need an actual directional light object. I used a 3DPoint and it works just fine

uniform int mat:hint_range(0, 3) = 3;//for switching between albedo and specular material setup
//0 = dark grey for directional lighting demo
//1 = default chrome
//2 = gold
//3 = individual albedo and specular material
uniform vec4 light_color:hint_color;
uniform vec3 light_coordinates;

uniform float sky_energy  : hint_range(0, 16) = 0.209; //skybox brightness
uniform mat3 camera_basis = mat3(1.0); //connect real world camera global_transform.basis here
uniform vec3 camera_global_position; //connect real world camera global_transform.origin here

uniform sampler2D texture_here; //2D skybox image here


const float PI = 3.14159265f;
const int BOUNCE = 7; //light bounce count

//const vec4 groundplane = vec4(0.707,0.707,0.0,10.0);
const vec4 groundplane = vec4(0.0,1.0,0.0,-10.0); //vec4(normal_vector.xyz,distance from origin along normal_vector)
const vec4 sphere1 = vec4(0.0,0.0,0.0,1.0); //vec4(global_transform.origin.xyz, radius)
const vec4 sphere3 = vec4(5.0,5.50,-10.0,3.0);

// wouldn't need these if I had Writable GPU Data Buffers :(
uniform vec3 sphere_o = vec3(0.0);
uniform vec3 sphere_o1 = vec3(0.0);
uniform vec3 sphere_o2 = vec3(0.0);
uniform vec3 sphere_o3 = vec3(0.0);
uniform vec3 sphere_o4 = vec3(0.0);
uniform vec3 sphere_o5 = vec3(0.0);
uniform vec3 sphere_o7 = vec3(0.0);
uniform vec3 sphere_o8 = vec3(0.0);
uniform vec3 sphere_o9 = vec3(0.0);
uniform vec3 sphere_o10 = vec3(0.0);
uniform vec3 sphere_o11 = vec3(0.0);

uniform vec2 PixelOffset = vec2(0f);
/*

the tutorial used structures to create Rays.

struct Ray
{
    float3 origin;
    float3 direction;
};

Godot 3 doesn't "support" structures (see what I-)
so, as a painful substitute, I used "inout" qualifiers to pass on "structure" values instead
I mean it works but the code could have been a lot shorter:

Ray CreateRay(float3 origin, float3 direction)
{
    Ray ray;
    ray.origin = origin;
    ray.direction = direction;
    return ray;
}

and that's just ONE of the reasons why I do NOT recommend what I'm doing
*/

void CreateRay(vec3 origin, vec3 direction, inout vec3 ray_origin, inout vec3 ray_direction, inout vec3 ray_energy)
{
    ray_origin = origin;
    ray_direction = direction;
    ray_energy = vec3(1.0, 1.0, 1.0);
}

//this creates a bunch of rays from your camera origin impaling your whole entire screen out to the virtual world
void CreateCameraRay(vec2 vps, vec2 coord,inout vec3 ray_origin,inout vec3 ray_direction,inout vec3 ray_energy)
{

	vec2 uv = (coord * 2.0 - vps)/(vps.y);
    vec3 ro = -camera_global_position;

	//vec3 rd = camera_basis * vec3(-uv,1.0);
	vec3 rd = camera_basis * vec3(-uv,1.0);
	

	rd = normalize(rd);
    CreateRay(ro, rd,ray_origin, ray_direction, ray_energy);
}
/*
initialises a "RayHit", basically 
where a ray hits (position), 
how far from the camera it hit something (distance), 
the surface normal ,
and the color (albedo) and shine(specular) of the surface it hit
*/
void CreateRayHit(inout vec3 hit_position,inout float hit_distance,inout vec3 hit_normal,inout vec3 hit_albedo,inout vec3 hit_specular,inout float hit_emission)
{

    hit_position = vec3(0.0f, 0.0f, 0.0f);
    hit_distance = 9999.0;
    hit_normal = vec3(0.0f, 0.0f, 0.0f);
	hit_albedo = vec3(0.0f, 0.0f, 0.0f);
	hit_specular = vec3(0.0f, 0.0f, 0.0f);
	hit_emission = 0.0f;

}


//uniform vec3 p1n = vec3(0f,1f,0f);//basis.z remember to negativise
uniform vec3 p1n = vec3(0.578881, -0.406075, -0.707107);
//uniform mat3 p1T_inv = mat3(vec3(1f,0f,0f),vec3(0f,1f,0f),vec3(0f,0f,1f));
//uniform mat3 p1T_inv = mat3(vec3(1, 0, 0), vec3(0, 0.707107, -0.707107), vec3(0, 0.707107, 0.707107));

//uniform mat3 p1T_inv = mat3(vec3(1f, 0f, 0f), vec3(0, -0.707107, 0.707107), vec3(0, -0.707107, -0.707107));
uniform mat3 p1T_inv = mat3(vec3(0.574277, 0.578881, -0.578881), vec3(0.818661, -0.406075, 0.406075), vec3(0, -0.707107, -0.707107));

uniform vec3 p1o;
uniform vec3 p1ox;
uniform vec2 plane_dimension=vec2(4f);

void IntersectBoundedPlane(vec3 ray_origin, vec3 ray_direction, inout vec3 bestHit_position,inout float bestHit_distance,inout vec3 bestHit_normal,inout vec3 bestHit_albedo, inout vec3 bestHit_specular,inout float bestHit_emission, vec3 pn, vec3 po,vec2 pdim, mat3 pT_inv, vec3 pox, vec3 plane_albedo,vec3 plane_specular,float plane_emission)
{
	float rdnpd = dot(-pn,(-po-ray_origin));
	if(rdnpd<0f){//culls back face
		float denominator = dot(-pn,ray_direction);
	    float t = rdnpd / denominator;
		vec3 rp = ray_origin + (ray_direction*t);
		float pw = pdim.x;//10f*0.5;// divided in half
		float ph = pdim.y;//5f*0.5;// divided in half
		//vec3 pox1 = pox;
		//vec3 pox1 = po * pT_inv;//calculated outside the shader, saves computation
		vec3 rpx = rp * pT_inv;

		//if(abs(-pox1.x - rpx.x)<=pw && abs(-pox1.z - rpx.z)<=ph){
		if(abs(-pox.x - rpx.x)<=pw && abs(-pox.z - rpx.z)<=ph){
		    if (t > 0.0 && t < bestHit_distance)
		    {
		        bestHit_distance = t;
		        bestHit_position = rp;
		        bestHit_normal = -pn;
				bestHit_albedo = plane_albedo;
				bestHit_specular = plane_specular;
		    }
		}
	}
}

//checks if a ray hits an infinite plane

void IntersectGroundPlane(vec3 ray_origin, vec3 ray_direction, inout vec3 bestHit_position,inout float bestHit_distance,inout vec3 bestHit_normal,inout vec3 bestHit_albedo, inout vec3 bestHit_specular,inout float bestHit_emission, vec3 pn, float pd,vec3 plane_albedo,vec3 plane_specular,float plane_emission)
{
    
    // Calculate distance along the ray where the ground plane is intersected
    
	float rdnpd = dot(-ray_origin, -pn)+pd;
	if(rdnpd<0f){//culls back face
		float denominator = dot(ray_direction, -pn);
	    float t = rdnpd / denominator;
		
		    if (t > 0.0 && t < bestHit_distance)
		    {
		        bestHit_distance = t;
		        bestHit_position = ray_origin + t * ray_direction;
		        bestHit_normal = -pn;
				bestHit_albedo = plane_albedo;
				bestHit_specular = plane_specular;
		    }
	}
}

//checks if a ray hits a sphere

void IntersectSphere(vec3 ray_origin, vec3 ray_direction, inout vec3 bestHit_position,inout float bestHit_distance,inout vec3 bestHit_normal,inout vec3 bestHit_albedo, inout vec3 bestHit_specular,inout float bestHit_emission, vec4 sphere,vec3 sphere_albedo,vec3 sphere_specular,float sphere_emission)
{
	float t = dot((sphere.xyz-ray_origin),ray_direction);
	vec3 p = ray_origin + ray_direction*t;
	float y = length(sphere.xyz-p);

	if(y<sphere.a){
		float x = abs(sqrt((sphere.a*sphere.a)-y*y));
		float t1 = t-x;
 
	    if (t1 > 0.0 && t1 < bestHit_distance)
	    {
	        bestHit_distance = t1;
	        bestHit_position = ray_origin + t1 * ray_direction;
	        bestHit_normal = normalize(bestHit_position - sphere.xyz);
			bestHit_albedo = sphere_albedo;
			bestHit_specular = sphere_specular;
			bestHit_emission = sphere_emission;
	    }
	}
/*
    float t = -1.0;
    float a = dot(ray_direction, ray_direction);
    vec3 s0_r0 = ray_origin - sphere.xyz;
    float b = 2.0 * dot(ray_direction, s0_r0);
    float c = dot(s0_r0, s0_r0) - (sphere.a * sphere.a);
    if (!(b*b - 4.0*a*c < 0.0)) {
        t = (-b - sqrt((b*b) - 4.0*a*c))/(2.0*a);
    }

    if (t > 0.0 && t < bestHit_distance)
    {
        bestHit_distance = t;
        bestHit_position = ray_origin + t * ray_direction;
        bestHit_normal = normalize(bestHit_position - sphere.xyz);
		bestHit_albedo = sphere_albedo;
		bestHit_specular = sphere_specular;
		bestHit_emission = sphere_emission;
    }
*/
}


/*
Here's where I tried to make constant arrays for defining individual material properties
Returns ERROR: Expected initialization of constants

const vec3 sphere_albedo[]={vec3(0.0,1.0,0.0),vec3(1.0, 0.78, 0.34),sphere_o1,vec3(0.20, 1.1, 0.80),vec3(1.0, 0.3, 0.84),vec3(0.0, 0.0, 0.0)};
const vec3 sphere_specular[]={vec3(0.04,0.04,0.04),vec3(1.0, 0.78, 0.34),sphere_o1,vec3(0.20, 1.1, 0.50),vec3(1.0, 0.3, 0.84),vec3(0.7, 0.7, 0.7)};

*/

//Traces each ray through the environment checking if it hits something along the way and adjusting color, lighting etc. accordingly

void Trace(vec3 ray_origin,vec3 ray_direction,vec3 ray_energy,out vec3 bestHit_position,out float bestHit_distance,out vec3 bestHit_normal,out vec3 bestHit_albedo,out vec3 bestHit_specular,out float bestHit_emission)
{
/*	
	this would have been way better with a for loop 
	but seeing that GPU Data buffers are still coming soon 
	and arrays are under renovation 
	I think this is good enough for now
*/
	CreateRayHit(bestHit_position, bestHit_distance, bestHit_normal,bestHit_albedo, bestHit_specular,bestHit_emission);
	
	IntersectBoundedPlane(ray_origin, ray_direction, bestHit_position, bestHit_distance, bestHit_normal,bestHit_albedo,bestHit_specular,bestHit_emission, p1n, p1o, plane_dimension,p1T_inv,p1ox,vec3(0.5),vec3(0.4),0f);
	IntersectGroundPlane(ray_origin, ray_direction, bestHit_position, bestHit_distance, bestHit_normal,bestHit_albedo,bestHit_specular,bestHit_emission, groundplane.xyz, groundplane.a,vec3(0.5),vec3(0.04),0f);
	IntersectSphere(ray_origin, ray_direction, bestHit_position, bestHit_distance, bestHit_normal, bestHit_albedo, bestHit_specular,bestHit_emission, sphere1,vec3(0.0),vec3(0.6),0f);
	IntersectSphere(ray_origin, ray_direction, bestHit_position, bestHit_distance, bestHit_normal, bestHit_albedo, bestHit_specular,bestHit_emission, sphere3,sphere3.xyz,vec3(0.04),0f);
	IntersectSphere(ray_origin, ray_direction, bestHit_position, bestHit_distance, bestHit_normal, bestHit_albedo, bestHit_specular,bestHit_emission, vec4(-sphere_o.xyz,5.0),vec3(0.0, 0.0, 0.0),vec3(1.0, 0.78, 0.34),0f);
	IntersectSphere(ray_origin, ray_direction, bestHit_position, bestHit_distance, bestHit_normal, bestHit_albedo, bestHit_specular,bestHit_emission, vec4(-sphere_o1.xyz,3.0),vec3(0.0, 0.0, 0.0),vec3(0.0, 1.0, 0.0),0f);
	IntersectSphere(ray_origin, ray_direction, bestHit_position, bestHit_distance, bestHit_normal, bestHit_albedo, bestHit_specular,bestHit_emission, vec4(-sphere_o2.xyz,5.0),vec3(0.20, 0.78, 0.84),vec3(0.20, 0.78, 0.84),0f);
	IntersectSphere(ray_origin, ray_direction, bestHit_position, bestHit_distance, bestHit_normal, bestHit_albedo, bestHit_specular,bestHit_emission, vec4(-sphere_o3.xyz,5.0),vec3(0.20, 0.0, 0.80),vec3(0.0, 0.0, 0.0),0f);
	IntersectSphere(ray_origin, ray_direction, bestHit_position, bestHit_distance, bestHit_normal, bestHit_albedo, bestHit_specular,bestHit_emission, vec4(-sphere_o4.xyz,5.0),vec3(0.01, 0.0, 1.0),vec3(0.01, 0.0, 1.0),0f);
	
	//IntersectSphere(ray_origin, ray_direction, bestHit_position, bestHit_distance, bestHit_normal, bestHit_albedo, bestHit_specular,bestHit_emission, vec4(-sphere_o8.xyz,7.0),vec3(100f, 0.0, 0.0),vec3(0.0001f),100f);
	//IntersectSphere(ray_origin, ray_direction, bestHit_position, bestHit_distance, bestHit_normal, bestHit_albedo, bestHit_specular,bestHit_emission, vec4(-sphere_o8.xyz,7.0),vec3(0.20, 0.78, 0.84),vec3(0.0001f),100f);
	//IntersectSphere(ray_origin, ray_direction, bestHit_position, bestHit_distance, bestHit_normal, bestHit_albedo, bestHit_specular,bestHit_emission, vec4(-sphere_o8.xyz,7.0),vec3(1.0, 0.78, 0.14),vec3(0.0001f),100f);
	vec3 light_control = d_light_energy * vec3(1.0, 0.78, 0.14);
	IntersectSphere(ray_origin, ray_direction, bestHit_position, bestHit_distance, bestHit_normal, bestHit_albedo, bestHit_specular,bestHit_emission, vec4(-sphere_o8.xyz,7.0),light_control,vec3(0.0001f),100f);	
	
	IntersectSphere(ray_origin, ray_direction, bestHit_position, bestHit_distance, bestHit_normal, bestHit_albedo, bestHit_specular,bestHit_emission, vec4(-sphere_o9.xyz,10.0),vec3(0.0),vec3(0.0157, 0.3882,0.0275),0f);
	IntersectSphere(ray_origin, ray_direction, bestHit_position, bestHit_distance, bestHit_normal, bestHit_albedo, bestHit_specular,bestHit_emission, vec4(-sphere_o10.xyz,10.0),vec3(0.3f, 0f, 1f),vec3(0.3f, 0f, 1.0),0f);
}

void TraceShadow(vec3 ray_origin,vec3 ray_direction,vec3 ray_energy,out vec3 bestHit_position,out float bestHit_distance,out vec3 bestHit_normal,out vec3 bestHit_albedo,out vec3 bestHit_specular,out float bestHit_emission)
{
/*	
	In tracing shadows, I would merge this with the function above if I could iterate thru the objects and skip over the emissive ones
	If I try and merge this with the other one I would need to perform a boolean check for each "IntersectSphere" function which is a pain
*/
	CreateRayHit(bestHit_position, bestHit_distance, bestHit_normal,bestHit_albedo, bestHit_specular,bestHit_emission);
	
	IntersectBoundedPlane(ray_origin, ray_direction, bestHit_position, bestHit_distance, bestHit_normal,bestHit_albedo,bestHit_specular,bestHit_emission, p1n, p1o, plane_dimension, p1T_inv, p1ox, vec3(0.5),vec3(0.4),0f);
	IntersectGroundPlane(ray_origin, ray_direction, bestHit_position, bestHit_distance, bestHit_normal,bestHit_albedo,bestHit_specular,bestHit_emission, groundplane.xyz, groundplane.a,vec3(0.80),vec3(0.04),0f);
	IntersectSphere(ray_origin, ray_direction, bestHit_position, bestHit_distance, bestHit_normal, bestHit_albedo, bestHit_specular,bestHit_emission, sphere1,vec3(0.0),vec3(0.6),0f);
	IntersectSphere(ray_origin, ray_direction, bestHit_position, bestHit_distance, bestHit_normal, bestHit_albedo, bestHit_specular,bestHit_emission, sphere3,sphere3.xyz,vec3(0.04),0f);
	IntersectSphere(ray_origin, ray_direction, bestHit_position, bestHit_distance, bestHit_normal, bestHit_albedo, bestHit_specular,bestHit_emission, vec4(-sphere_o.xyz,5.0),vec3(0.0, 0.0, 0.0),vec3(1.0, 0.78, 0.34),0f);
	IntersectSphere(ray_origin, ray_direction, bestHit_position, bestHit_distance, bestHit_normal, bestHit_albedo, bestHit_specular,bestHit_emission, vec4(-sphere_o1.xyz,3.0),vec3(0.0, 0.0, 0.0),vec3(0.0, 1.0, 0.0),0f);
	IntersectSphere(ray_origin, ray_direction, bestHit_position, bestHit_distance, bestHit_normal, bestHit_albedo, bestHit_specular,bestHit_emission, vec4(-sphere_o2.xyz,5.0),vec3(0.20, 0.78, 0.84),vec3(0.20, 0.78, 0.84),0f);
	IntersectSphere(ray_origin, ray_direction, bestHit_position, bestHit_distance, bestHit_normal, bestHit_albedo, bestHit_specular,bestHit_emission, vec4(-sphere_o3.xyz,5.0),vec3(0.80, 0.10, 0.0),vec3(0.80, 0.10, 0.0),0f);
	IntersectSphere(ray_origin, ray_direction, bestHit_position, bestHit_distance, bestHit_normal, bestHit_albedo, bestHit_specular,bestHit_emission, vec4(-sphere_o4.xyz,5.0),vec3(0.01, 0.0, 1.0),vec3(0.01, 0.0, 1.0),0f);
	
	IntersectSphere(ray_origin, ray_direction, bestHit_position, bestHit_distance, bestHit_normal, bestHit_albedo, bestHit_specular,bestHit_emission, vec4(-sphere_o9.xyz,10.0),vec3(0.0157, 0.3882,0.0275),vec3(0.0157, 0.3882,0.0275),0f);
	IntersectSphere(ray_origin, ray_direction, bestHit_position, bestHit_distance, bestHit_normal, bestHit_albedo, bestHit_specular,bestHit_emission, vec4(-sphere_o10.xyz,10.0),vec3(0.3f, 0f, 1f),vec3(0.3f, 0f, 1.0),0f);
}

// here's where everything on the screen is coloured in
vec3 Shade(inout vec3 ray_origin,inout vec3 ray_direction,inout vec3 ray_energy, vec3 hit_position,float hit_distance,vec3 hit_normal,vec3 hit_albedo,vec3 hit_specular,float hit_emission)
{
	
    if (hit_distance < 9900.0)// basically when a ray hits something
    {
		 ray_origin = hit_position + hit_normal * 0.001f; // have to offset the ray origin a little to stop the ray from getting caught behind the surface it's suppose to bounce off of
        // Reflect the ray and multiply energy with specular reflection
		vec3 albedo;
        vec3 specular;
		float emission = 0f;
		vec3 light_dir = d_light_dir;
		vec3 light_origin;
		vec3 light_albedo = light_color.xyz;
		float light_dist = 9900f;
		
		if(!sun){
			//light_origin = ray_origin + light_coordinates;
			light_origin = ray_origin + sphere_o8.xyz;
			
			light_dist = length(light_origin);
			
			light_dir = normalize(light_origin);
			//light_albedo = light_color.xyz;
			//light_albedo = vec3(0.20, 0.78, 0.84);
			light_albedo = vec3(1.0, 0.78, 0.34);
		}
		
		switch(mat){
			case 0:{
				specular = vec3(0.04);//shaded
				//vec3 albedo = vec3(0.0,0.0,0.70);//blue
				albedo = vec3(0.80);//gray
				break;
			}
			case 1:{//default
				specular = vec3(0.6);
				albedo = vec3(1.0);
				break;
			}
			case 2:{
				specular = vec3(1.0f, 0.78f, 0.34f);//shinny gold
				albedo = vec3(1.0f, 0.78f, 0.34f);
				break;
			}
			default:{
				albedo = hit_albedo;
				emission = hit_emission;
				specular = hit_specular;
				break;
			}
		}


       	ray_direction = reflect(ray_direction, hit_normal);
       	ray_energy *= specular;
		

		if(shadow)// surprisingly shadows are their own rays but backwards
		{
			vec3 shadowRay_origin;
			vec3 shadowRay_direction;
			vec3 shadowRay_energy;
			
			//CreateRay(ray_origin,-d_light_dir, shadowRay_origin, shadowRay_direction, shadowRay_energy);
			CreateRay(ray_origin,-light_dir, shadowRay_origin, shadowRay_direction, shadowRay_energy);
			vec3 shadowHit_position;
			float shadowHit_distance;
			vec3 shadowHit_normal;
			vec3 shadowHit_albedo;
			vec3 shadowHit_specular;
			float shadowHit_emission;
			//shadow rays skip over emissive objects
			TraceShadow(shadowRay_origin,shadowRay_direction,shadowRay_energy,shadowHit_position,shadowHit_distance,shadowHit_normal,shadowHit_albedo,shadowHit_specular,shadowHit_emission);

			//if (shadowHit_distance <= 9900.0)// if the shadow Ray hits something (ie the ray is blocked from reaching infinity) the passed on light ray energy is multiplied by 0.0
			if (shadowHit_distance <= light_dist)
			{
				return vec3(0.0)+albedo*emission * light_albedo; // basically a shadow
			}
			if(emission > 0f){
				return emission*albedo;
			}else{
				//return clamp(dot(hit_normal, d_light_dir)*-1.0,0.0,1.0) * d_light_energy * albedo; //every other ray gets to be coloured in
				return clamp(dot(hit_normal, light_dir)*-1.0,0.0,1.0) * d_light_energy* albedo * light_albedo ; //every other ray gets to be coloured in
			}
			
		}
		else{ //else if shadows are disabled
				return emission*albedo;

			//return clamp(dot(hit_normal, d_light_dir)*-1.0,0.0,1.0) * d_light_energy * albedo; //colors pixel by albedo and d_light
			//return vec3(0.0, 0.0, 0.0);// Return nothing
			/*
			//default black
			return vec3(0.0, 0.0, 0.0);// Return nothing

			 at the end of each trace if the ray hits anything, the pixel that the ray is attached to is initially coloured black
			 as the ray bounces around the scene it should eventually reach infinity(9900.0f), shooting off into the sky
			 only then is the pixel coloured with a sample from the sky texture on the next else statement
			 if the ray kept bouncing, exceeding the "BOUNCE" limit, 
			 it's left as is: a black spot on the screen (specifically on the reflective sphere/plane) where the light never escaped			 
*/	 
		}
        
    }
    else
    {
        // Erase the ray's energy - the sky doesn't reflect anything
        ray_energy = vec3(0.0);
	
// this samples the 2D texture as if it was a sphere	
		float theta = acos(ray_direction.y) / -PI;
		float phi = atan(ray_direction.x, ray_direction.z) / -PI * 0.5f;
		return textureLod(texture_here,vec2(phi,theta),0).xyz*sky_energy;//needs to be textureLod else a weird line appears in sample

/*//from ShaderToy Test
        //For 2D texture only
        float theta = acos(ray.direction.y) / -PI;
        float phi = atan(ray.direction.x, -ray.direction.z) / -PI * 0.5f;
        return texture(iChannel0, vec2(phi, theta)).xyz;
		//For Cubemaps
        //return texture(texture_here, ray_direction).xyz;//texture
        //return ray_direction* 0.5 + 0.5;//uv rainbow
*/
    }
}

void fragment() {
	if(active){
		vec3 ray_origin;
		vec3 ray_direction;
		vec3 ray_energy;
		
		vec3 hit_position;
		float hit_distance;
		vec3 hit_normal;
		vec3 hit_albedo;
		vec3 hit_specular;
		float hit_emission;

		CreateCameraRay(VIEWPORT_SIZE,FRAGCOORD.xy,ray_origin,ray_direction,ray_energy);
    
	    vec3 result = vec3(0.0, 0.0, 0.0);
	    vec3 m_ray_energy;

	    for (int i = 0; i < BOUNCE; i++)
	    {
			m_ray_energy=ray_energy; 

	        Trace(ray_origin,ray_direction,ray_energy,hit_position,hit_distance,hit_normal,hit_albedo,hit_specular,hit_emission);

			result += m_ray_energy * Shade(ray_origin,ray_direction,ray_energy, hit_position,hit_distance,hit_normal,hit_albedo,hit_specular,hit_emission);
/*
			here's the original code snippet from the tutorial blog:
				result += ray.energy * Shade(ray, hit);

			I had to make it remember the last ray_energy value (hence: "m_ray_energy") since the "Shade" function kept changing it right before it gets multiplied
*/

	        if (all(lessThan(ray_energy, vec3(0.001)))) break; // this breaks out of the loop if the ray_energy drops too low
								// apparently GLSL's built in "any" function takes in binary vectors as inputs, different from HLSL's (Unity's Compute Shader)
								
	    }
		ALBEDO = result;
		ALPHA = 1.80;
	}
}

