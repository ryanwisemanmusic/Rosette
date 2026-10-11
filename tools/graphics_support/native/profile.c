// Read capabilities only. No VkDevice, pipelines, command buffers or queues.
#define VK_NO_PROTOTYPES
#define VK_ENABLE_BETA_EXTENSIONS
#include <vulkan/vulkan.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#define FN(n) PFN_vk##n n = (PFN_vk##n)dlsym(lib, "vk" #n); if (!n) return 2
#define CHECK(x) if ((x) != VK_SUCCESS) return 3
int main(int argc, char** argv) {
  if (argc != 2) return 2;
  void* lib = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
  if (!lib) { fprintf(stderr, "%s\n", dlerror()); return 2; }
  FN(CreateInstance); FN(DestroyInstance); FN(EnumeratePhysicalDevices);
  FN(GetPhysicalDeviceFeatures2); FN(GetPhysicalDeviceProperties2);
  VkApplicationInfo app = {.sType=VK_STRUCTURE_TYPE_APPLICATION_INFO, .apiVersion=VK_API_VERSION_1_2};
  VkInstanceCreateInfo info = {.sType=VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, .pApplicationInfo=&app};
  VkInstance instance; CHECK(CreateInstance(&info, NULL, &instance));
  uint32_t count = 1; VkPhysicalDevice device;
  CHECK(EnumeratePhysicalDevices(instance, &count, &device));
  VkPhysicalDevicePortabilitySubsetFeaturesKHR portability = {.sType=VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PORTABILITY_SUBSET_FEATURES_KHR};
  VkPhysicalDeviceShaderDemoteToHelperInvocationFeaturesEXT demote = {
    .sType=VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_DEMOTE_TO_HELPER_INVOCATION_FEATURES_EXT, .pNext=&portability};
  VkPhysicalDeviceFragmentShaderInterlockFeaturesEXT interlock = {
    .sType=VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FRAGMENT_SHADER_INTERLOCK_FEATURES_EXT, .pNext=&demote};
  VkPhysicalDeviceFeatures2 features = {.sType=VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2, .pNext=&interlock};
  GetPhysicalDeviceFeatures2(device, &features);
  VkPhysicalDeviceFloatControlsProperties floats = {.sType=VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FLOAT_CONTROLS_PROPERTIES};
  VkPhysicalDeviceProperties2 properties = {.sType=VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2, .pNext=&floats};
  GetPhysicalDeviceProperties2(device, &properties);
  const VkPhysicalDeviceFeatures* f = &features.features;
  const VkPhysicalDeviceProperties* p = &properties.properties;
  unsigned values[] = {f->fullDrawIndexUint32, f->vertexPipelineStoresAndAtomics,
    f->fragmentStoresAndAtomics, f->shaderClipDistance, f->shaderCullDistance,
    portability.imageViewFormatSwizzle, floats.shaderSignedZeroInfNanPreserveFloat32,
    floats.shaderDenormFlushToZeroFloat32, floats.shaderRoundingModeRTEFloat32,
    interlock.fragmentShaderSampleInterlock, demote.shaderDemoteToHelperInvocation};
  const char* names[] = {"full_draw_index_uint32", "vertex_pipeline_stores_and_atomics",
    "fragment_stores_and_atomics", "clip_distance", "cull_distance", "image_view_format_swizzle",
    "signed_zero_inf_nan_preserve_float32", "denorm_flush_to_zero_float32", "rounding_mode_rte_float32",
    "fragment_shader_sample_interlock", "demote_to_helper_invocation"};
  unsigned mask=0; for (unsigned i=0;i<11;++i) if(values[i]) mask |= 1u<<i;
  printf("{\"device\":\"%s\",\"driver_version\":%u,\"api_version\":%u,\"feature_mask\":%u,\"spirv_version\":%u,\"max_storage_buffer_range\":%u",
    p->deviceName,p->driverVersion,p->apiVersion,mask,p->apiVersion>=VK_API_VERSION_1_2 ? 0x10500 : 0x10300,p->limits.maxStorageBufferRange);
  for (unsigned i=0;i<11;++i) printf(",\"%s\":%s",names[i],values[i]?"true":"false");
  printf("}\n"); DestroyInstance(instance,NULL); dlclose(lib);
  return f->fragmentStoresAndAtomics && interlock.fragmentShaderSampleInterlock ? 0 : 4;
}
