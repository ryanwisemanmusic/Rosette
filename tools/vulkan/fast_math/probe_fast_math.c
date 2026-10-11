// Runs fast_math.comp once on the given MoltenVK and prints its special-value
// results. The fast-math mode comes from the environment exactly as Rosette
// applies it (MVK_CONFIG_FAST_MATH_ENABLED, set before the driver is opened),
// so running it once with 0 and once with 1 shows whether the setting reaches
// the Metal compiler. No game shader is dispatched.
//
//   probe_fast_math DRIVER.dylib SHADER.spv MODE(0|1)
#include <dlfcn.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define VK_NO_PROTOTYPES
#include <vulkan/vulkan.h>

#define FUNCTIONS(X)                                                                          \
  X(CreateInstance) X(EnumeratePhysicalDevices) X(GetPhysicalDeviceMemoryProperties)          \
  X(GetPhysicalDeviceQueueFamilyProperties) X(CreateDevice) X(GetDeviceQueue)                 \
  X(CreateBuffer) X(GetBufferMemoryRequirements) X(AllocateMemory) X(BindBufferMemory)        \
  X(MapMemory) X(CreateDescriptorSetLayout) X(CreatePipelineLayout) X(CreateDescriptorPool)   \
  X(AllocateDescriptorSets) X(UpdateDescriptorSets) X(CreateShaderModule)                     \
  X(CreateComputePipelines) X(CreateCommandPool) X(AllocateCommandBuffers)                    \
  X(BeginCommandBuffer) X(EndCommandBuffer) X(CmdBindPipeline) X(CmdBindDescriptorSets)       \
  X(CmdDispatch) X(QueueSubmit) X(CreateFence) X(WaitForFences)
#define DECLARE(n) static PFN_vk##n vk##n;
FUNCTIONS(DECLARE)

#define CHECK(e)                                                                         \
  do {                                                                                   \
    VkResult r_ = (e);                                                                   \
    if (r_ != VK_SUCCESS) {                                                              \
      fprintf(stderr, "%s failed: %d\n", #e, r_);                                        \
      exit(2);                                                                           \
    }                                                                                    \
  } while (0)

int main(int argc, char **argv) {
  if (argc != 4) {
    fprintf(stderr, "usage: probe_fast_math DRIVER.dylib SHADER.spv MODE\n");
    return 2;
  }
  setenv("MVK_CONFIG_FAST_MATH_ENABLED", argv[3], 1);
  void *library = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
  if (!library) {
    fprintf(stderr, "%s\n", dlerror());
    return 2;
  }
#define LOAD(n)                                         \
  vk##n = (PFN_vk##n)dlsym(library, "vk" #n);           \
  if (!vk##n) {                                         \
    fprintf(stderr, "driver lacks vk%s\n", #n);         \
    return 2;                                           \
  }
  FUNCTIONS(LOAD)

  VkApplicationInfo app = {.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
                           .pApplicationName = "Rosette fast-math probe",
                           .apiVersion = VK_API_VERSION_1_2};
  VkInstanceCreateInfo instance_info = {.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
                                        .pApplicationInfo = &app};
  VkInstance instance;
  CHECK(vkCreateInstance(&instance_info, NULL, &instance));
  uint32_t count = 1;
  VkPhysicalDevice physical;
  CHECK(vkEnumeratePhysicalDevices(instance, &count, &physical));
  VkPhysicalDeviceMemoryProperties memory;
  vkGetPhysicalDeviceMemoryProperties(physical, &memory);
  float priority = 1;
  VkDeviceQueueCreateInfo queue_info = {.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
                                        .queueFamilyIndex = 0,
                                        .queueCount = 1,
                                        .pQueuePriorities = &priority};
  const char *extensions[] = {"VK_KHR_portability_subset"};
  VkDeviceCreateInfo device_info = {.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
                                    .queueCreateInfoCount = 1,
                                    .pQueueCreateInfos = &queue_info,
                                    .enabledExtensionCount = 1,
                                    .ppEnabledExtensionNames = extensions};
  VkDevice device;
  CHECK(vkCreateDevice(physical, &device_info, NULL, &device));
  VkQueue queue;
  vkGetDeviceQueue(device, 0, 0, &queue);

  const VkDeviceSize size = 4096;
  VkBufferCreateInfo buffer_info = {.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
                                    .size = size,
                                    .usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT};
  VkBuffer buffer;
  CHECK(vkCreateBuffer(device, &buffer_info, NULL, &buffer));
  VkMemoryRequirements requirements;
  vkGetBufferMemoryRequirements(device, buffer, &requirements);
  uint32_t type = UINT32_MAX;
  const VkMemoryPropertyFlags wanted =
      VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
  for (uint32_t i = 0; i < memory.memoryTypeCount; i++)
    if ((requirements.memoryTypeBits & (1u << i)) &&
        (memory.memoryTypes[i].propertyFlags & wanted) == wanted) {
      type = i;
      break;
    }
  if (type == UINT32_MAX) return 2;
  VkMemoryAllocateInfo allocate = {.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
                                   .allocationSize = requirements.size,
                                   .memoryTypeIndex = type};
  VkDeviceMemory device_memory;
  CHECK(vkAllocateMemory(device, &allocate, NULL, &device_memory));
  CHECK(vkBindBufferMemory(device, buffer, device_memory, 0));
  float *data;
  CHECK(vkMapMemory(device, device_memory, 0, size, 0, (void **)&data));
  memset(data, 0xA5, size);  // results must overwrite this guard pattern
  data[0] = 0.0f;
  data[1] = INFINITY;
  data[2] = NAN;
  data[3] = 1.0f;

  FILE *file = fopen(argv[2], "rb");
  if (!file) return 2;
  fseek(file, 0, SEEK_END);
  long bytes = ftell(file);
  fseek(file, 0, SEEK_SET);
  uint32_t *code = malloc((size_t)bytes);
  if (fread(code, 1, (size_t)bytes, file) != (size_t)bytes) return 2;
  fclose(file);
  VkShaderModuleCreateInfo module_info = {.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
                                          .codeSize = (size_t)bytes,
                                          .pCode = code};
  VkShaderModule module;
  CHECK(vkCreateShaderModule(device, &module_info, NULL, &module));

  VkDescriptorSetLayoutBinding binding = {.binding = 0,
                                          .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
                                          .descriptorCount = 1,
                                          .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT};
  VkDescriptorSetLayoutCreateInfo set_layout_info = {
      .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
      .bindingCount = 1,
      .pBindings = &binding};
  VkDescriptorSetLayout set_layout;
  CHECK(vkCreateDescriptorSetLayout(device, &set_layout_info, NULL, &set_layout));
  VkPipelineLayoutCreateInfo layout_info = {.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
                                            .setLayoutCount = 1,
                                            .pSetLayouts = &set_layout};
  VkPipelineLayout layout;
  CHECK(vkCreatePipelineLayout(device, &layout_info, NULL, &layout));
  VkComputePipelineCreateInfo pipeline_info = {
      .sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
      .stage = {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                .stage = VK_SHADER_STAGE_COMPUTE_BIT,
                .module = module,
                .pName = "main"},
      .layout = layout};
  VkPipeline pipeline;
  CHECK(vkCreateComputePipelines(device, VK_NULL_HANDLE, 1, &pipeline_info, NULL, &pipeline));
  VkDescriptorPoolSize pool_size = {.type = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .descriptorCount = 1};
  VkDescriptorPoolCreateInfo pool_info = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
                                          .maxSets = 1,
                                          .poolSizeCount = 1,
                                          .pPoolSizes = &pool_size};
  VkDescriptorPool pool;
  CHECK(vkCreateDescriptorPool(device, &pool_info, NULL, &pool));
  VkDescriptorSetAllocateInfo set_info = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
                                          .descriptorPool = pool,
                                          .descriptorSetCount = 1,
                                          .pSetLayouts = &set_layout};
  VkDescriptorSet set;
  CHECK(vkAllocateDescriptorSets(device, &set_info, &set));
  VkDescriptorBufferInfo descriptor = {.buffer = buffer, .offset = 0, .range = size};
  VkWriteDescriptorSet write = {.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                                .dstSet = set,
                                .descriptorCount = 1,
                                .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
                                .pBufferInfo = &descriptor};
  vkUpdateDescriptorSets(device, 1, &write, 0, NULL);

  VkCommandPoolCreateInfo command_pool_info = {.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
                                               .queueFamilyIndex = 0};
  VkCommandPool command_pool;
  CHECK(vkCreateCommandPool(device, &command_pool_info, NULL, &command_pool));
  VkCommandBufferAllocateInfo command_info = {.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
                                              .commandPool = command_pool,
                                              .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY,
                                              .commandBufferCount = 1};
  VkCommandBuffer command;
  CHECK(vkAllocateCommandBuffers(device, &command_info, &command));
  VkCommandBufferBeginInfo begin = {.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
  CHECK(vkBeginCommandBuffer(command, &begin));
  vkCmdBindPipeline(command, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
  vkCmdBindDescriptorSets(command, VK_PIPELINE_BIND_POINT_COMPUTE, layout, 0, 1, &set, 0, NULL);
  vkCmdDispatch(command, 1, 1, 1);
  CHECK(vkEndCommandBuffer(command));
  VkFenceCreateInfo fence_info = {.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO};
  VkFence fence;
  CHECK(vkCreateFence(device, &fence_info, NULL, &fence));
  VkSubmitInfo submit = {.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
                         .commandBufferCount = 1,
                         .pCommandBuffers = &command};
  CHECK(vkQueueSubmit(queue, 1, &submit, fence));
  // Bounded wait: a dispatch of one invocation that does not finish in ten
  // seconds is a failure, never retried.
  CHECK(vkWaitForFences(device, 1, &fence, VK_TRUE, 10000000000ull));

  static const char *names[] = {
      "isnan(NaN)",           "isinf(+inf)",          "legacy_mul(0,inf)", "isnan(0*inf)",
      "clamp(NaN,0,31.875)",  "min(max(NaN,0),31.875)", "isnan(inf-inf)",   "exp2(-inf)",
      "log2(0)==-inf",        "NaN!=NaN",             "isinf(1/0)"};
  printf("mode=MVK_CONFIG_FAST_MATH_ENABLED=%s\n", argv[3]);
  for (int i = 0; i < 11; i++) {
    uint32_t raw;
    memcpy(&raw, &data[4 + i], 4);
    printf("%-24s %-14g bits=0x%08x\n", names[i], data[4 + i], raw);
  }
  return 0;
}
