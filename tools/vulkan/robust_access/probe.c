// Native GPU proof for Rosette's robust-access transform
// (lib/gpu/vulkan/robust_access.zig). No Xenia, no Rosette guest, no window.
//
//   probe patterns DRIVER.dylib DIR
//     DIR holds NAME.spv and NAME.hardened.spv for each pattern shader and
//     fullscreen.spv. Each pattern is an access Xenia's generated shaders make
//     and that only robustBufferAccess keeps inside its buffer.
//   probe uniform-zero DRIVER.dylib DIR
//     Only the hardened relative-constant compute shader is dispatched.
//     This is the safe default regression for negative and extreme indices.
//   probe fsi-corpus DRIVER.dylib ORIGINAL_DIR HARDENED_DIR VERTEX.spv
//     runs every fragment-shader-interlock module in ORIGINAL_DIR, and its
//     hardened twin from HARDENED_DIR, through Xenia's attachment-less FSI
//     pass with a descriptor layout reflected from the module, and compares
//     every EDRAM word they leave.
//
// The fsi-corpus mode executes original game shaders and has faulted the GPU
// even with its supposedly sane constants. Do not use it as a routine gate.
// The device is created with robustBufferAccess enabled, exactly as Xenia
// creates its own. Every buffer carries guard space inside its own
// allocation, so an original shader's out-of-range access lands on sentinel
// words instead of an unmapped page: the probe observes the access without
// faulting the GPU. Indices that reach far outside any allocation run only
// against the hardened shaders. MVK_CONFIG_RESUME_LOST_DEVICE=0 turns any
// Metal command-buffer failure into VK_ERROR_DEVICE_LOST, which fails the run.
#define VK_NO_PROTOTYPES
#include <vulkan/vulkan.h>
#include <dirent.h>
#include <dlfcn.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define FUNCTIONS(X) \
  X(CmdFillBuffer) X(CreateInstance) X(DestroyInstance) X(EnumeratePhysicalDevices) X(GetPhysicalDeviceProperties) \
  X(GetPhysicalDeviceFeatures2) X(GetPhysicalDeviceMemoryProperties) X(GetPhysicalDeviceQueueFamilyProperties) \
  X(EnumerateDeviceExtensionProperties) X(CreateDevice) X(DestroyDevice) X(GetDeviceQueue) X(DeviceWaitIdle) \
  X(CreateBuffer) X(DestroyBuffer) X(GetBufferMemoryRequirements) X(AllocateMemory) X(FreeMemory) \
  X(BindBufferMemory) X(MapMemory) X(CreateImage) X(DestroyImage) X(GetImageMemoryRequirements) \
  X(BindImageMemory) X(CreateImageView) X(DestroyImageView) X(CreateSampler) X(DestroySampler) \
  X(CreateDescriptorSetLayout) X(DestroyDescriptorSetLayout) X(CreatePipelineLayout) X(DestroyPipelineLayout) \
  X(CreateDescriptorPool) X(DestroyDescriptorPool) X(ResetDescriptorPool) X(AllocateDescriptorSets) \
  X(UpdateDescriptorSets) X(CreateShaderModule) X(DestroyShaderModule) X(CreateRenderPass) X(DestroyRenderPass) \
  X(CreateFramebuffer) X(DestroyFramebuffer) X(CreateGraphicsPipelines) X(CreateComputePipelines) \
  X(DestroyPipeline) X(CreateCommandPool) X(DestroyCommandPool) X(AllocateCommandBuffers) X(ResetCommandBuffer) \
  X(BeginCommandBuffer) X(EndCommandBuffer) X(CmdBeginRenderPass) X(CmdEndRenderPass) X(CmdBindPipeline) \
  X(CmdBindDescriptorSets) X(CmdDraw) X(CmdDispatch) X(CmdPushConstants) X(CmdPipelineBarrier) \
  X(CmdClearColorImage) X(CmdCopyBufferToImage) X(QueueSubmit) X(CreateFence) X(DestroyFence) X(WaitForFences) X(ResetFences)
#define DECLARE(n) static PFN_vk##n vk##n;
FUNCTIONS(DECLARE)

static int failures;
#define CHECK(e)                                                       \
  do {                                                                 \
    VkResult check_result = (e);                                       \
    if (check_result != VK_SUCCESS) {                                  \
      fprintf(stderr, "%s:%d %s failed: %d\n", __FILE__, __LINE__, #e, \
              check_result);                                           \
      exit(2);                                                         \
    }                                                                  \
  } while (0)
#define EXPECT(condition, ...)              \
  do {                                      \
    int expect_ok = (condition);            \
    printf("%s ", expect_ok ? "PASS" : "FAIL"); \
    printf(__VA_ARGS__);                    \
    printf("\n");                           \
    if (!expect_ok) failures++;             \
  } while (0)

static VkInstance instance;
static VkPhysicalDevice physical;
static VkDevice device;
static VkQueue queue;
static uint32_t family;
static VkCommandPool command_pool;
static VkCommandBuffer command;
static VkFence fence;
static VkPhysicalDeviceMemoryProperties memory_properties;

// -- Setup ------------------------------------------------------------------

static void create_device(const char *driver) {
  setenv("MVK_CONFIG_FAST_MATH_ENABLED", "0", 1);  // Rosette's production setting
  setenv("MVK_CONFIG_RESUME_LOST_DEVICE", "0", 1);  // a GPU fault fails the run
  void *library = dlopen(driver, RTLD_NOW | RTLD_LOCAL);
  if (!library) {
    fprintf(stderr, "%s\n", dlerror());
    exit(2);
  }
#define LOAD(n)                                        \
  vk##n = (PFN_vk##n)dlsym(library, "vk" #n);          \
  if (!vk##n) {                                        \
    fprintf(stderr, "driver lacks vk%s\n", #n);        \
    exit(2);                                           \
  }
  FUNCTIONS(LOAD)
  VkApplicationInfo app = {.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
                           .pApplicationName = "Rosette robust-access probe",
                           .apiVersion = VK_API_VERSION_1_2};
  VkInstanceCreateInfo instance_info = {.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
                                        .pApplicationInfo = &app};
  CHECK(vkCreateInstance(&instance_info, NULL, &instance));
  uint32_t count = 1;
  CHECK(vkEnumeratePhysicalDevices(instance, &count, &physical));
  VkPhysicalDeviceProperties properties;
  vkGetPhysicalDeviceProperties(physical, &properties);
  vkGetPhysicalDeviceMemoryProperties(physical, &memory_properties);
  VkPhysicalDeviceFragmentShaderInterlockFeaturesEXT interlock = {
      .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FRAGMENT_SHADER_INTERLOCK_FEATURES_EXT};
  VkPhysicalDeviceFeatures2 features = {.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,
                                        .pNext = &interlock};
  vkGetPhysicalDeviceFeatures2(physical, &features);
  printf("driver=%s device=%s driverVersion=%u robustBufferAccess(reported)=%u\n", driver,
         properties.deviceName, properties.driverVersion, features.features.robustBufferAccess);
  if (!interlock.fragmentShaderSampleInterlock || !features.features.fragmentStoresAndAtomics) {
    fprintf(stderr, "FSI prerequisites missing\n");
    exit(2);
  }
  interlock.fragmentShaderShadingRateInterlock = VK_FALSE;
  VkPhysicalDeviceFeatures enabled = {
      // Xenia enables robustBufferAccess (ui/vulkan/vulkan_device.cc) and its
      // shaders rely on it; enable it here too, so the original shaders run
      // under the same promise MoltenVK makes to Xenia.
      .robustBufferAccess = features.features.robustBufferAccess,
      .fragmentStoresAndAtomics = VK_TRUE,
      .vertexPipelineStoresAndAtomics = features.features.vertexPipelineStoresAndAtomics,
      .sampleRateShading = VK_TRUE,
      .independentBlend = features.features.independentBlend,
  };
  const char *extensions[2] = {VK_EXT_FRAGMENT_SHADER_INTERLOCK_EXTENSION_NAME};
  uint32_t extension_count = 1, available = 0;
  CHECK(vkEnumerateDeviceExtensionProperties(physical, NULL, &available, NULL));
  VkExtensionProperties *names = calloc(available, sizeof(*names));
  CHECK(vkEnumerateDeviceExtensionProperties(physical, NULL, &available, names));
  for (uint32_t i = 0; i < available; i++)
    if (!strcmp(names[i].extensionName, "VK_KHR_portability_subset"))
      extensions[extension_count++] = "VK_KHR_portability_subset";
  free(names);
  uint32_t families = 0;
  vkGetPhysicalDeviceQueueFamilyProperties(physical, &families, NULL);
  VkQueueFamilyProperties *family_properties = calloc(families, sizeof(*family_properties));
  vkGetPhysicalDeviceQueueFamilyProperties(physical, &families, family_properties);
  family = UINT32_MAX;
  for (uint32_t i = 0; i < families; i++)
    if ((family_properties[i].queueFlags & (VK_QUEUE_GRAPHICS_BIT | VK_QUEUE_COMPUTE_BIT)) ==
        (VK_QUEUE_GRAPHICS_BIT | VK_QUEUE_COMPUTE_BIT)) {
      family = i;
      break;
    }
  free(family_properties);
  if (family == UINT32_MAX) exit(2);
  float priority = 1;
  VkDeviceQueueCreateInfo queue_info = {.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
                                        .queueFamilyIndex = family,
                                        .queueCount = 1,
                                        .pQueuePriorities = &priority};
  VkDeviceCreateInfo device_info = {.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
                                    .pNext = &interlock,
                                    .queueCreateInfoCount = 1,
                                    .pQueueCreateInfos = &queue_info,
                                    .enabledExtensionCount = extension_count,
                                    .ppEnabledExtensionNames = extensions,
                                    .pEnabledFeatures = &enabled};
  CHECK(vkCreateDevice(physical, &device_info, NULL, &device));
  vkGetDeviceQueue(device, family, 0, &queue);
  VkCommandPoolCreateInfo pool_info = {.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
                                       .flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
                                       .queueFamilyIndex = family};
  CHECK(vkCreateCommandPool(device, &pool_info, NULL, &command_pool));
  VkCommandBufferAllocateInfo allocate = {.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
                                          .commandPool = command_pool,
                                          .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY,
                                          .commandBufferCount = 1};
  CHECK(vkAllocateCommandBuffers(device, &allocate, &command));
  VkFenceCreateInfo fence_info = {.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO};
  CHECK(vkCreateFence(device, &fence_info, NULL, &fence));
}

static void begin(void) {
  CHECK(vkResetCommandBuffer(command, 0));
  VkCommandBufferBeginInfo info = {.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
                                   .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT};
  CHECK(vkBeginCommandBuffer(command, &info));
}

// Submit and wait. A Metal command-buffer failure becomes VK_ERROR_DEVICE_LOST
// here, and the probe stops: one fault is enough to prove the access escaped.
static void submit_and_wait(const char *what) {
  VkMemoryBarrier host = {.sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER,
                          .srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT,
                          .dstAccessMask = VK_ACCESS_HOST_READ_BIT};
  vkCmdPipelineBarrier(command, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, VK_PIPELINE_STAGE_HOST_BIT, 0, 1,
                       &host, 0, NULL, 0, NULL);
  CHECK(vkEndCommandBuffer(command));
  VkSubmitInfo submit = {.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
                         .commandBufferCount = 1,
                         .pCommandBuffers = &command};
  CHECK(vkResetFences(device, 1, &fence));
  VkResult result = vkQueueSubmit(queue, 1, &submit, fence);
  if (result == VK_SUCCESS) result = vkWaitForFences(device, 1, &fence, VK_TRUE, 10000000000ull);
  if (result != VK_SUCCESS) {
    printf("FAIL %s: the GPU work did not complete (VkResult=%d); a Metal fault or hang\n", what, result);
    exit(1);
  }
}

static uint32_t memory_type(uint32_t bits, VkMemoryPropertyFlags wanted) {
  for (uint32_t i = 0; i < memory_properties.memoryTypeCount; i++)
    if ((bits & (1u << i)) && (memory_properties.memoryTypes[i].propertyFlags & wanted) == wanted) return i;
  fprintf(stderr, "no memory type 0x%x\n", wanted);
  exit(2);
}

typedef struct {
  VkBuffer buffer;
  VkDeviceMemory memory;
  uint32_t *words;
  VkDeviceSize size;
} Buffer;

// A host-visible buffer in its own allocation, so its end is the
// allocation's end, as with Xenia's dedicated EDRAM and shared memory.
static Buffer buffer_create(VkDeviceSize size, VkBufferUsageFlags usage) {
  Buffer buffer = {.size = size};
  VkBufferCreateInfo info = {.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO, .size = size, .usage = usage};
  CHECK(vkCreateBuffer(device, &info, NULL, &buffer.buffer));
  VkMemoryRequirements requirements;
  vkGetBufferMemoryRequirements(device, buffer.buffer, &requirements);
  VkMemoryAllocateInfo allocate = {
      .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
      .allocationSize = requirements.size,
      .memoryTypeIndex = memory_type(requirements.memoryTypeBits,
                                     VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)};
  CHECK(vkAllocateMemory(device, &allocate, NULL, &buffer.memory));
  CHECK(vkBindBufferMemory(device, buffer.buffer, buffer.memory, 0));
  CHECK(vkMapMemory(device, buffer.memory, 0, VK_WHOLE_SIZE, 0, (void **)&buffer.words));
  return buffer;
}

static void buffer_destroy(Buffer *buffer) {
  vkDestroyBuffer(device, buffer->buffer, NULL);
  vkFreeMemory(device, buffer->memory, NULL);
}

static uint32_t *read_file(const char *path, size_t *size_out) {
  FILE *file = fopen(path, "rb");
  if (!file) return NULL;
  fseek(file, 0, SEEK_END);
  long size = ftell(file);
  rewind(file);
  if (size < 20 || size % 4) {
    fclose(file);
    return NULL;
  }
  uint32_t *words = malloc((size_t)size);
  if (fread(words, 1, (size_t)size, file) != (size_t)size) {
    fclose(file);
    free(words);
    return NULL;
  }
  fclose(file);
  *size_out = (size_t)size;
  return words;
}

static VkShaderModule module_from_words(const uint32_t *words, size_t size) {
  VkShaderModuleCreateInfo info = {.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
                                   .codeSize = size,
                                   .pCode = words};
  VkShaderModule module;
  CHECK(vkCreateShaderModule(device, &info, NULL, &module));
  return module;
}

static VkShaderModule module_from_file(const char *dir, const char *name) {
  char path[4096];
  snprintf(path, sizeof(path), "%s/%s", dir, name);
  size_t size;
  uint32_t *words = read_file(path, &size);
  if (!words) {
    fprintf(stderr, "cannot read %s\n", path);
    exit(2);
  }
  VkShaderModule module = module_from_words(words, size);
  free(words);
  return module;
}

static VkDescriptorSetLayout set_layout(const VkDescriptorType *types, uint32_t count, VkShaderStageFlags stages) {
  VkDescriptorSetLayoutBinding bindings[8];
  for (uint32_t i = 0; i < count; i++)
    bindings[i] = (VkDescriptorSetLayoutBinding){
        .binding = i, .descriptorType = types[i], .descriptorCount = 1, .stageFlags = stages};
  VkDescriptorSetLayoutCreateInfo info = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
                                          .bindingCount = count,
                                          .pBindings = bindings};
  VkDescriptorSetLayout layout;
  CHECK(vkCreateDescriptorSetLayout(device, &info, NULL, &layout));
  return layout;
}

static VkDescriptorPool make_pool(void) {
  VkDescriptorPoolSize sizes[] = {{VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 64},
                                  {VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 64},
                                  {VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE, 128},
                                  {VK_DESCRIPTOR_TYPE_SAMPLER, 128}};
  VkDescriptorPoolCreateInfo info = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
                                     .maxSets = 16,
                                     .poolSizeCount = 4,
                                     .pPoolSizes = sizes};
  VkDescriptorPool pool;
  CHECK(vkCreateDescriptorPool(device, &info, NULL, &pool));
  return pool;
}

static VkDescriptorSet allocate_set(VkDescriptorPool pool, VkDescriptorSetLayout layout) {
  VkDescriptorSetAllocateInfo info = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
                                      .descriptorPool = pool,
                                      .descriptorSetCount = 1,
                                      .pSetLayouts = &layout};
  VkDescriptorSet set;
  CHECK(vkAllocateDescriptorSets(device, &info, &set));
  return set;
}

static void write_buffer(VkDescriptorSet set, uint32_t binding, VkDescriptorType type, VkBuffer buffer,
                         VkDeviceSize offset, VkDeviceSize range) {
  VkDescriptorBufferInfo info = {buffer, offset, range};
  VkWriteDescriptorSet write = {.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                                .dstSet = set,
                                .dstBinding = binding,
                                .descriptorCount = 1,
                                .descriptorType = type,
                                .pBufferInfo = &info};
  vkUpdateDescriptorSets(device, 1, &write, 0, NULL);
}

static VkPipeline compute_pipeline(VkPipelineLayout layout, VkShaderModule module) {
  VkComputePipelineCreateInfo info = {
      .sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
      .stage = {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                .stage = VK_SHADER_STAGE_COMPUTE_BIT,
                .module = module,
                .pName = "main"},
      .layout = layout};
  VkPipeline pipeline;
  CHECK(vkCreateComputePipelines(device, VK_NULL_HANDLE, 1, &info, NULL, &pipeline));
  return pipeline;
}

// Xenia's FSI render pass: no attachments, one subpass, and by-region
// fragment-shader dependencies on both sides (vulkan_render_target_cache.cc).
static VkRenderPass fsi_render_pass(void) {
  VkSubpassDescription subpass = {.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS};
  VkAccessFlags access = VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_SHADER_WRITE_BIT;
  VkSubpassDependency dependencies[2] = {
      {VK_SUBPASS_EXTERNAL, 0, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
       access, access, VK_DEPENDENCY_BY_REGION_BIT},
      {0, VK_SUBPASS_EXTERNAL, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
       access, access, VK_DEPENDENCY_BY_REGION_BIT}};
  VkRenderPassCreateInfo info = {.sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
                                 .subpassCount = 1,
                                 .pSubpasses = &subpass,
                                 .dependencyCount = 2,
                                 .pDependencies = dependencies};
  VkRenderPass pass;
  CHECK(vkCreateRenderPass(device, &info, NULL, &pass));
  return pass;
}

static VkFramebuffer fsi_framebuffer(VkRenderPass pass, uint32_t width, uint32_t height) {
  VkFramebufferCreateInfo info = {.sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
                                  .renderPass = pass,
                                  .width = width,
                                  .height = height,
                                  .layers = 1};
  VkFramebuffer framebuffer;
  CHECK(vkCreateFramebuffer(device, &info, NULL, &framebuffer));
  return framebuffer;
}

static VkResult graphics_pipeline(VkRenderPass pass, VkPipelineLayout layout, VkShaderModule vertex,
                                  VkShaderModule fragment, VkSampleCountFlagBits samples, uint32_t width,
                                  uint32_t height, VkPipeline *out) {
  VkPipelineShaderStageCreateInfo stages[2] = {
      {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
       .stage = VK_SHADER_STAGE_VERTEX_BIT,
       .module = vertex,
       .pName = "main"},
      {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
       .stage = VK_SHADER_STAGE_FRAGMENT_BIT,
       .module = fragment,
       .pName = "main"}};
  VkPipelineVertexInputStateCreateInfo vertex_input = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO};
  VkPipelineInputAssemblyStateCreateInfo assembly = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
      .topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST};
  VkViewport viewport = {0, 0, (float)width, (float)height, 0, 1};
  VkRect2D scissor = {{0, 0}, {width, height}};
  VkPipelineViewportStateCreateInfo viewport_state = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
      .viewportCount = 1,
      .pViewports = &viewport,
      .scissorCount = 1,
      .pScissors = &scissor};
  VkPipelineRasterizationStateCreateInfo raster = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
      .polygonMode = VK_POLYGON_MODE_FILL,
      .cullMode = VK_CULL_MODE_NONE,
      .frontFace = VK_FRONT_FACE_COUNTER_CLOCKWISE,
      .lineWidth = 1};
  VkPipelineMultisampleStateCreateInfo multisample = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
      .rasterizationSamples = samples};
  VkPipelineColorBlendStateCreateInfo blend = {.sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO};
  VkPipelineDepthStencilStateCreateInfo depth = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO};
  VkGraphicsPipelineCreateInfo info = {.sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
                                       .stageCount = 2,
                                       .pStages = stages,
                                       .pVertexInputState = &vertex_input,
                                       .pInputAssemblyState = &assembly,
                                       .pViewportState = &viewport_state,
                                       .pRasterizationState = &raster,
                                       .pMultisampleState = &multisample,
                                       .pDepthStencilState = &depth,
                                       .pColorBlendState = &blend,
                                       .layout = layout,
                                       .renderPass = pass};
  return vkCreateGraphicsPipelines(device, VK_NULL_HANDLE, 1, &info, NULL, out);
}

static uint32_t sentinel_hits(const uint32_t *words, size_t first, size_t count, uint32_t sentinel) {
  uint32_t changed = 0;
  for (size_t i = first; i < first + count; i++) changed += words[i] != sentinel;
  return changed;
}

// -- Patterns -----------------------------------------------------------------

static const char *pattern_dir;
static VkShaderModule pattern_module(const char *name, int hardened) {
  char file[256];
  snprintf(file, sizeof(file), "%s%s.spv", name, hardened ? ".hardened" : "");
  return module_from_file(pattern_dir, file);
}

// Xenia's vertex fetch: the word is loaded, then zeroed past the fetch
// constant's end. The loaded value is used twice, so the load is a separate
// Metal statement and runs whatever the bound check says.
static void pattern_vertex_fetch(void) {
  const uint32_t range_words = 262144;  // 1 MiB bound; 1 MiB guard after it
  const uint32_t sentinel = 0xBADC0DE5;
  Buffer shared = buffer_create(2u << 20, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);
  Buffer result = buffer_create(256, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);
  for (uint32_t i = 0; i < range_words; i++) shared.words[i] = i;
  for (uint32_t i = range_words; i < 2 * range_words; i++) shared.words[i] = sentinel;
  VkDescriptorType types[2] = {VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER};
  VkDescriptorSetLayout layout_set = set_layout(types, 2, VK_SHADER_STAGE_COMPUTE_BIT);
  VkPushConstantRange push = {VK_SHADER_STAGE_COMPUTE_BIT, 0, 8};
  VkPipelineLayoutCreateInfo layout_info = {.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
                                            .setLayoutCount = 1,
                                            .pSetLayouts = &layout_set,
                                            .pushConstantRangeCount = 1,
                                            .pPushConstantRanges = &push};
  VkPipelineLayout layout;
  CHECK(vkCreatePipelineLayout(device, &layout_info, NULL, &layout));
  VkDescriptorPool pool = make_pool();
  VkDescriptorSet set = allocate_set(pool, layout_set);
  write_buffer(set, 0, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, shared.buffer, 0, range_words * 4ull);
  write_buffer(set, 1, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, result.buffer, 0, 256);
  struct {
    int32_t address, fetch_end;
    int original;
  } cases[] = {{1234, (int32_t)range_words, 1},
               {(int32_t)range_words + 100, 1000, 1},
               {INT32_MAX, 1000, 0},
               {INT32_MIN, 1000, 0},
               {-1, 1000, 0}};
  for (int hardened = 0; hardened < 2; hardened++) {
    VkShaderModule module = pattern_module("vertex_fetch", hardened);
    VkPipeline pipeline = compute_pipeline(layout, module);
    for (size_t c = 0; c < sizeof(cases) / sizeof(cases[0]); c++) {
      if (!hardened && !cases[c].original) continue;
      memset(result.words, 0xEE, 256);
      begin();
      vkCmdBindPipeline(command, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
      vkCmdBindDescriptorSets(command, VK_PIPELINE_BIND_POINT_COMPUTE, layout, 0, 1, &set, 0, NULL);
      int32_t constants[2] = {cases[c].address, cases[c].fetch_end};
      vkCmdPushConstants(command, layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, 8, constants);
      vkCmdDispatch(command, 1, 1, 1);
      submit_and_wait("vertex_fetch");
      uint32_t loaded = result.words[0], selected = result.words[1];
      int32_t address = cases[c].address;
      int in_range = address >= 0 && (uint32_t)address < range_words;
      uint32_t expected_select = (uint32_t)address < (uint32_t)cases[c].fetch_end ? (in_range ? (uint32_t)address : 0) : 0;
      if (in_range) {
        EXPECT(loaded == (uint32_t)address && selected == expected_select,
               "vertex_fetch %s address=%d in range: loaded=%u selected=%u", hardened ? "hardened" : "original",
               address, loaded, selected);
      } else if (!hardened) {
        // The original reads past the bound range: the word it returns is
        // the guard's, which robustBufferAccess forbids.
        EXPECT(loaded == sentinel && selected == 0,
               "vertex_fetch original address=%d reads OUTSIDE the bound range (loaded=0x%08x from the guard)",
               address, loaded);
      } else {
        EXPECT(loaded == range_words - 1 && selected == 0,
               "vertex_fetch hardened address=%d stays in range: loaded=%u (last element) selected=%u", address,
               loaded, selected);
      }
    }
    vkDestroyPipeline(device, pipeline, NULL);
    vkDestroyShaderModule(device, module, NULL);
  }
  vkDestroyDescriptorPool(device, pool, NULL);
  vkDestroyPipelineLayout(device, layout, NULL);
  vkDestroyDescriptorSetLayout(device, layout_set, NULL);
  buffer_destroy(&shared);
  buffer_destroy(&result);
}

// Xenia's relative constant read: float_constants[a0 + 16], 256 entries, no
// clamp. The constants sit in the middle of an allocation with a guard on
// each side, like a constant block inside Xenia's upload pool.
static void pattern_relative_constant(int hardened_only) {
  const uint32_t lower = 0xC0FFEE00, upper = 0xBADC0DE5;
  Buffer constants = buffer_create(12288, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);
  Buffer result = buffer_create(256, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);
  for (uint32_t i = 0; i < 1024; i++) constants.words[i] = lower;
  for (uint32_t i = 0; i < 256; i++) {
    float value = (float)i;
    for (uint32_t j = 0; j < 4; j++) memcpy(&constants.words[1024 + i * 4 + j], &value, 4);
  }
  for (uint32_t i = 2048; i < 3072; i++) constants.words[i] = upper;
  VkDescriptorType types[2] = {VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER};
  VkDescriptorSetLayout layout_set = set_layout(types, 2, VK_SHADER_STAGE_COMPUTE_BIT);
  VkPushConstantRange push = {VK_SHADER_STAGE_COMPUTE_BIT, 0, 4};
  VkPipelineLayoutCreateInfo layout_info = {.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
                                            .setLayoutCount = 1,
                                            .pSetLayouts = &layout_set,
                                            .pushConstantRangeCount = 1,
                                            .pPushConstantRanges = &push};
  VkPipelineLayout layout;
  CHECK(vkCreatePipelineLayout(device, &layout_info, NULL, &layout));
  VkDescriptorPool pool = make_pool();
  VkDescriptorSet set = allocate_set(pool, layout_set);
  write_buffer(set, 0, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, constants.buffer, 4096, 4096);
  write_buffer(set, 1, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, result.buffer, 0, 256);
  struct {
    int32_t a0;
    int original;
  } cases[] = {{0, 1}, {239, 1}, {240, 1}, {-16, 1}, {-17, 1}, {300, 1}, {-100, 1},
               {1000000, 0}, {-1000000, 0}, {INT32_MIN, 0}, {INT32_MAX, 0}};
  for (int hardened = hardened_only ? 1 : 0; hardened < 2; hardened++) {
    VkShaderModule module = pattern_module("relative_constant", hardened);
    VkPipeline pipeline = compute_pipeline(layout, module);
    for (size_t c = 0; c < sizeof(cases) / sizeof(cases[0]); c++) {
      if (!hardened && !cases[c].original) continue;
      memset(result.words, 0xEE, 256);
      begin();
      vkCmdBindPipeline(command, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
      vkCmdBindDescriptorSets(command, VK_PIPELINE_BIND_POINT_COMPUTE, layout, 0, 1, &set, 0, NULL);
      vkCmdPushConstants(command, layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, 4, &cases[c].a0);
      vkCmdDispatch(command, 1, 1, 1);
      submit_and_wait("relative_constant");
      uint32_t bits = result.words[0];
      float value;
      memcpy(&value, &bits, 4);
      uint32_t index = (uint32_t)cases[c].a0 + 16u;
      if (index < 256) {
        EXPECT(value == (float)index, "relative_constant %s a0=%d reads c[%d]=%g",
               hardened ? "hardened" : "original", cases[c].a0, index, value);
      } else if (!hardened) {
        EXPECT(bits == ((int32_t)index < 0 ? lower : upper),
               "relative_constant original a0=%d reads OUTSIDE the bound range (0x%08x from the %s guard)",
               cases[c].a0, bits, (int32_t)index < 0 ? "lower" : "upper");
      } else {
        EXPECT(bits == 0, "relative_constant hardened a0=%d returns zero, bounded load=%g", cases[c].a0,
               value);
      }
    }
    vkDestroyPipeline(device, pipeline, NULL);
    vkDestroyShaderModule(device, module, NULL);
  }
  vkDestroyDescriptorPool(device, pool, NULL);
  vkDestroyPipelineLayout(device, layout, NULL);
  vkDestroyDescriptorSetLayout(device, layout_set, NULL);
  buffer_destroy(&constants);
  buffer_destroy(&result);
}

// A memexport-style store at a shader-formed address.
// Safe HDR conversion test. The CPU oracle evaluates the numeric format,
// independently of the GPU's findMSB, bitfield insert and rounding sequence.
static uint32_t color7e3_bits(uint32_t code) {
  uint32_t exponent = code >> 7, mantissa = code & 127u;
  float value = exponent ? ldexpf((float)(128u + mantissa), (int)exponent - 10)
                         : (float)mantissa / 512.0f;
  uint32_t bits;
  memcpy(&bits, &value, 4);
  return bits;
}

static void pattern_color_math(void) {
  const uint32_t output_words = 1024u * 16u, guard_words = 64, sentinel = 0xbadc0de5;
  Buffer output = buffer_create((output_words + guard_words) * 4ull, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);
  Buffer upload = buffer_create(1024u * 4ull, VK_BUFFER_USAGE_TRANSFER_SRC_BIT);
  for (uint32_t code = 0; code < 1024; code++)
    upload.words[code] = code | (((code * 7u) & 1023u) << 10) |
                        (((code * 23u) & 1023u) << 20) | ((code & 3u) << 30);
  VkImage image;
  VkImageCreateInfo image_info = {.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
                                 .imageType = VK_IMAGE_TYPE_2D, .format = VK_FORMAT_A2B10G10R10_UNORM_PACK32,
                                 .extent = {32, 32, 1}, .mipLevels = 1, .arrayLayers = 1,
                                 .samples = VK_SAMPLE_COUNT_1_BIT, .tiling = VK_IMAGE_TILING_OPTIMAL,
                                 .usage = VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT};
  CHECK(vkCreateImage(device, &image_info, NULL, &image));
  VkMemoryRequirements requirements;
  vkGetImageMemoryRequirements(device, image, &requirements);
  VkDeviceMemory image_memory;
  VkMemoryAllocateInfo allocate = {.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
                                  .allocationSize = requirements.size,
                                  .memoryTypeIndex = memory_type(requirements.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)};
  CHECK(vkAllocateMemory(device, &allocate, NULL, &image_memory));
  CHECK(vkBindImageMemory(device, image, image_memory, 0));
  VkImageView views[2];
  VkImageViewCreateInfo view_info = {.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
                                   .image = image, .viewType = VK_IMAGE_VIEW_TYPE_2D,
                                   .format = image_info.format,
                                   .subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1}};
  CHECK(vkCreateImageView(device, &view_info, NULL, &views[0]));
  // Exactly the observed Halo pre-gamma view: components=5/0/3/2.
  view_info.components = (VkComponentMapping){VK_COMPONENT_SWIZZLE_B, VK_COMPONENT_SWIZZLE_IDENTITY,
                                             VK_COMPONENT_SWIZZLE_R, VK_COMPONENT_SWIZZLE_ONE};
  CHECK(vkCreateImageView(device, &view_info, NULL, &views[1]));
  VkSampler sampler;
  VkSamplerCreateInfo sampler_info = {.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
                                     .magFilter = VK_FILTER_NEAREST, .minFilter = VK_FILTER_NEAREST,
                                     .addressModeU = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
                                     .addressModeV = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
                                     .addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE};
  CHECK(vkCreateSampler(device, &sampler_info, NULL, &sampler));
  begin();
  VkImageMemoryBarrier barrier = {.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
                                 .dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT,
                                 .oldLayout = VK_IMAGE_LAYOUT_UNDEFINED,
                                 .newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                                 .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
                                 .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
                                 .image = image, .subresourceRange = view_info.subresourceRange};
  vkCmdPipelineBarrier(command, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0,
                       0, NULL, 0, NULL, 1, &barrier);
  VkBufferImageCopy copy = {.imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1}, .imageExtent = {32, 32, 1}};
  vkCmdCopyBufferToImage(command, upload.buffer, image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &copy);
  barrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
  barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
  barrier.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
  barrier.newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
  vkCmdPipelineBarrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0,
                       0, NULL, 0, NULL, 1, &barrier);
  submit_and_wait("color image upload");
  VkDescriptorType types[] = {VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE,
                             VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE, VK_DESCRIPTOR_TYPE_SAMPLER};
  VkDescriptorSetLayout layout_set = set_layout(types, 4, VK_SHADER_STAGE_COMPUTE_BIT);
  VkPipelineLayoutCreateInfo layout_info = {.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
                                          .setLayoutCount = 1, .pSetLayouts = &layout_set};
  VkPipelineLayout layout;
  CHECK(vkCreatePipelineLayout(device, &layout_info, NULL, &layout));
  VkDescriptorPool pool = make_pool();
  VkDescriptorSet set = allocate_set(pool, layout_set);
  write_buffer(set, 0, types[0], output.buffer, 0, output_words * 4ull);
  VkDescriptorImageInfo image_descriptors[] = {
      {.imageView = views[0], .imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL},
      {.imageView = views[1], .imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL},
      {.sampler = sampler}};
  VkWriteDescriptorSet image_writes[3];
  for (uint32_t i = 0; i < 3; i++)
    image_writes[i] = (VkWriteDescriptorSet){.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                                           .dstSet = set, .dstBinding = i + 1, .descriptorCount = 1,
                                           .descriptorType = types[i + 1], .pImageInfo = &image_descriptors[i]};
  vkUpdateDescriptorSets(device, 3, image_writes, 0, NULL);
  for (int hardened = 0; hardened < 2; hardened++) {
    VkShaderModule module = pattern_module("color_math", hardened);
    VkPipeline pipeline = compute_pipeline(layout, module);
    for (uint32_t i = 0; i < output_words + guard_words; i++) output.words[i] = sentinel;
    begin();
    vkCmdBindPipeline(command, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
    vkCmdBindDescriptorSets(command, VK_PIPELINE_BIND_POINT_COMPUTE, layout, 0, 1, &set, 0, NULL);
    vkCmdDispatch(command, 16, 1, 1);
    submit_and_wait("color_math");
    uint32_t bad[8] = {0}, bad_views[2] = {0};
    for (uint32_t code = 0; code < 1024; code++) {
      uint32_t packed = code | (((code * 7u) & 1023u) << 10) |
                        (((code * 23u) & 1023u) << 20) | ((code & 3u) << 30);
      float alpha = (float)(code & 3u) / 3.0f;
      uint32_t alpha_bits;
      memcpy(&alpha_bits, &alpha, 4);
      uint32_t expected[8] = {color7e3_bits(code), code,
                             code == 1023 ? code : code + (code & 1u),
                             color7e3_bits(code), color7e3_bits((code * 7u) & 1023u),
                             color7e3_bits((code * 23u) & 1023u), packed, alpha_bits};
      for (uint32_t j = 0; j < 8; j++) {
        if (output.words[code * 16u + j] != expected[j]) {
          if (!bad[j]) printf("first mismatch column=%u code=%u got=0x%08x expected=0x%08x\n",
                              j, code, output.words[code * 16u + j], expected[j]);
          bad[j]++;
        }
      }
      float rgba[4] = {(float)code / 1023.0f, (float)((code * 7u) & 1023u) / 1023.0f,
                       (float)((code * 23u) & 1023u) / 1023.0f, alpha};
      float swapped[4] = {rgba[2], rgba[1], rgba[0], 1.0f};
      for (uint32_t channel = 0; channel < 4; channel++) {
        float identity, swap;
        memcpy(&identity, &output.words[code * 16u + 8u + channel], 4);
        memcpy(&swap, &output.words[code * 16u + 12u + channel], 4);
        // UNORM sampling may round; detect channel/format mistakes rather
        // than requiring a particular implementation of division by 1023.
        bad_views[0] += !(fabsf(identity - rgba[channel]) <= 0.0000002f);
        bad_views[1] += !(fabsf(swap - swapped[channel]) <= 0.0000002f);
      }
    }
    const char *names[] = {"decode", "round_trip", "round_even_midpoint", "packed_R",
                           "packed_G", "packed_B", "packed_round_trip", "alpha"};
    for (uint32_t j = 0; j < 8; j++)
      EXPECT(bad[j] == 0, "color_math %s %s 1024 codes mismatches=%u", hardened ? "hardened" : "original", names[j], bad[j]);
    EXPECT(bad_views[0] == 0, "color_math %s A2B10G10R10 identity view 4096 components mismatches=%u", hardened ? "hardened" : "original", bad_views[0]);
    EXPECT(bad_views[1] == 0, "color_math %s A2B10G10R10 B/G/R/One view 4096 components mismatches=%u", hardened ? "hardened" : "original", bad_views[1]);
    uint32_t bad_guards = 0;
    for (uint32_t i = output_words; i < output_words + guard_words; i++) bad_guards += output.words[i] != sentinel;
    EXPECT(bad_guards == 0, "color_math %s guard intact", hardened ? "hardened" : "original");
    vkDestroyPipeline(device, pipeline, NULL);
    vkDestroyShaderModule(device, module, NULL);
  }
  vkDestroyDescriptorPool(device, pool, NULL);
  vkDestroyPipelineLayout(device, layout, NULL);
  vkDestroyDescriptorSetLayout(device, layout_set, NULL);
  vkDestroySampler(device, sampler, NULL);
  vkDestroyImageView(device, views[0], NULL);
  vkDestroyImageView(device, views[1], NULL);
  vkDestroyImage(device, image, NULL);
  vkFreeMemory(device, image_memory, NULL);
  buffer_destroy(&upload);
  buffer_destroy(&output);
}

static void pattern_export_store(void) {
  const uint32_t range_words = 262144;
  const uint32_t sentinel = 0xBADC0DE5;
  Buffer shared = buffer_create(2u << 20, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);
  VkDescriptorType types[1] = {VK_DESCRIPTOR_TYPE_STORAGE_BUFFER};
  VkDescriptorSetLayout layout_set = set_layout(types, 1, VK_SHADER_STAGE_COMPUTE_BIT);
  VkPushConstantRange push = {VK_SHADER_STAGE_COMPUTE_BIT, 0, 8};
  VkPipelineLayoutCreateInfo layout_info = {.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
                                            .setLayoutCount = 1,
                                            .pSetLayouts = &layout_set,
                                            .pushConstantRangeCount = 1,
                                            .pPushConstantRanges = &push};
  VkPipelineLayout layout;
  CHECK(vkCreatePipelineLayout(device, &layout_info, NULL, &layout));
  VkDescriptorPool pool = make_pool();
  VkDescriptorSet set = allocate_set(pool, layout_set);
  write_buffer(set, 0, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, shared.buffer, 0, range_words * 4ull);
  struct {
    int32_t address;
    uint32_t value;
    int original;
  } cases[] = {{77, 0x11, 1}, {(int32_t)range_words + 5, 0x22, 1}, {INT32_MAX, 0x33, 0}, {INT32_MIN, 0x44, 0}};
  for (int hardened = 0; hardened < 2; hardened++) {
    VkShaderModule module = pattern_module("export_store", hardened);
    VkPipeline pipeline = compute_pipeline(layout, module);
    for (size_t c = 0; c < sizeof(cases) / sizeof(cases[0]); c++) {
      if (!hardened && !cases[c].original) continue;
      memset(shared.words, 0, range_words * 4ull);
      for (uint32_t i = range_words; i < 2 * range_words; i++) shared.words[i] = sentinel;
      begin();
      vkCmdBindPipeline(command, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
      vkCmdBindDescriptorSets(command, VK_PIPELINE_BIND_POINT_COMPUTE, layout, 0, 1, &set, 0, NULL);
      int32_t constants[2] = {cases[c].address, (int32_t)cases[c].value};
      vkCmdPushConstants(command, layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, 8, constants);
      vkCmdDispatch(command, 1, 1, 1);
      submit_and_wait("export_store");
      uint32_t guard_writes = sentinel_hits(shared.words, range_words, range_words, sentinel);
      int32_t address = cases[c].address;
      if (address >= 0 && (uint32_t)address < range_words) {
        EXPECT(shared.words[address] == cases[c].value && guard_writes == 0,
               "export_store %s address=%d writes in range, guard intact", hardened ? "hardened" : "original",
               address);
      } else if (!hardened) {
        EXPECT(guard_writes == 1 && shared.words[address] == cases[c].value,
               "export_store original address=%d writes OUTSIDE the bound range (%u guard word changed)", address,
               guard_writes);
      } else {
        EXPECT(guard_writes == 0 && shared.words[range_words - 1] == cases[c].value,
               "export_store hardened address=%d stays in range: last element written, guard intact", address);
      }
    }
    vkDestroyPipeline(device, pipeline, NULL);
    vkDestroyShaderModule(device, module, NULL);
  }
  vkDestroyDescriptorPool(device, pool, NULL);
  vkDestroyPipelineLayout(device, layout, NULL);
  vkDestroyDescriptorSetLayout(device, layout_set, NULL);
  buffer_destroy(&shared);
}

// An interlocked store through Xenia's FSI pass shape, with indices running
// past the 10 MiB EDRAM range.
static void pattern_interlocked_store(void) {
  const uint32_t edram_words = 2621440, guard_words = 16384, width = 80, height = 16;
  const uint32_t sentinel = 0xBADC0DE5, marker = 0xA5A5A5A5;
  Buffer edram = buffer_create((edram_words + guard_words) * 4ull, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);
  VkDescriptorType types[1] = {VK_DESCRIPTOR_TYPE_STORAGE_BUFFER};
  VkDescriptorSetLayout layout_set = set_layout(types, 1, VK_SHADER_STAGE_FRAGMENT_BIT);
  VkPushConstantRange push = {VK_SHADER_STAGE_FRAGMENT_BIT, 0, 8};
  VkPipelineLayoutCreateInfo layout_info = {.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
                                            .setLayoutCount = 1,
                                            .pSetLayouts = &layout_set,
                                            .pushConstantRangeCount = 1,
                                            .pPushConstantRanges = &push};
  VkPipelineLayout layout;
  CHECK(vkCreatePipelineLayout(device, &layout_info, NULL, &layout));
  VkDescriptorPool pool = make_pool();
  VkDescriptorSet set = allocate_set(pool, layout_set);
  write_buffer(set, 0, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, edram.buffer, 0, edram_words * 4ull);
  VkRenderPass pass = fsi_render_pass();
  VkFramebuffer framebuffer = fsi_framebuffer(pass, width, height);
  VkShaderModule vertex = module_from_file(pattern_dir, "fullscreen.spv");
  struct {
    int32_t base;
    int original;
  } cases[] = {{0, 1}, {(int32_t)edram_words - 640, 1}, {0x7FFFF000, 0}, {-0x7FFFF000, 0}};
  for (int hardened = 0; hardened < 2; hardened++) {
    VkShaderModule fragment = pattern_module("interlocked_store", hardened);
    VkPipeline pipeline;
    CHECK(graphics_pipeline(pass, layout, vertex, fragment, VK_SAMPLE_COUNT_1_BIT, width, height, &pipeline));
    for (size_t c = 0; c < sizeof(cases) / sizeof(cases[0]); c++) {
      if (!hardened && !cases[c].original) continue;
      memset(edram.words, 0, edram_words * 4ull);
      for (uint32_t i = edram_words; i < edram_words + guard_words; i++) edram.words[i] = sentinel;
      begin();
      vkCmdBindPipeline(command, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);
      vkCmdBindDescriptorSets(command, VK_PIPELINE_BIND_POINT_GRAPHICS, layout, 0, 1, &set, 0, NULL);
      int32_t constants[2] = {cases[c].base, (int32_t)marker};
      vkCmdPushConstants(command, layout, VK_SHADER_STAGE_FRAGMENT_BIT, 0, 8, constants);
      VkRenderPassBeginInfo begin_pass = {.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
                                          .renderPass = pass,
                                          .framebuffer = framebuffer,
                                          .renderArea = {{0, 0}, {width, height}}};
      vkCmdBeginRenderPass(command, &begin_pass, VK_SUBPASS_CONTENTS_INLINE);
      vkCmdDraw(command, 3, 1, 0, 0);
      vkCmdEndRenderPass(command);
      submit_and_wait("interlocked_store");
      uint32_t guard_writes = sentinel_hits(edram.words, edram_words, guard_words, sentinel);
      uint32_t in_range = 0;
      for (uint32_t i = 0; i < edram_words; i++) in_range += edram.words[i] == marker;
      int64_t first = cases[c].base, last = first + width * height - 1;
      if (first >= 0 && last < edram_words) {
        EXPECT(guard_writes == 0 && in_range == width * height,
               "interlocked_store %s base=%d writes %u in-range words, guard intact",
               hardened ? "hardened" : "original", cases[c].base, in_range);
      } else if (!hardened) {
        EXPECT(guard_writes > 0, "interlocked_store original base=%d writes OUTSIDE the bound range (%u guard words)",
               cases[c].base, guard_writes);
      } else {
        EXPECT(guard_writes == 0 && edram.words[edram_words - 1] == marker,
               "interlocked_store hardened base=%d stays in range (guard intact, %u in-range words)", cases[c].base,
               in_range);
      }
    }
    vkDestroyPipeline(device, pipeline, NULL);
    vkDestroyShaderModule(device, fragment, NULL);
  }
  vkDestroyShaderModule(device, vertex, NULL);
  vkDestroyFramebuffer(device, framebuffer, NULL);
  vkDestroyRenderPass(device, pass, NULL);
  vkDestroyDescriptorPool(device, pool, NULL);
  vkDestroyPipelineLayout(device, layout, NULL);
  vkDestroyDescriptorSetLayout(device, layout_set, NULL);
  buffer_destroy(&edram);
}

// -- FSI corpus ---------------------------------------------------------------

enum { kMaxSets = 4, kMaxBindings = 64 };

typedef struct {
  int used;
  VkDescriptorType type;
  VkImageViewType view;
  int integer;  // sampled type: 0 float, 1 uint, 2 sint
} Binding;

typedef struct {
  Binding bindings[kMaxSets][kMaxBindings];
  uint32_t push_constant_bytes;
  int fsi;
  int fragment;
} Reflection;

// Enough of SPIR-V to rebuild Xenia's descriptor layout for one module.
static int reflect(const uint32_t *words, size_t word_count, Reflection *out) {
  memset(out, 0, sizeof(*out));
  uint32_t bound = words[3];
  uint32_t *set_of = calloc(bound, 4), *binding_of = calloc(bound, 4), *has_set = calloc(bound, 4);
  uint32_t *type_op = calloc(bound, 4), *type_a = calloc(bound, 4), *type_b = calloc(bound, 4),
           *type_c = calloc(bound, 4), *type_d = calloc(bound, 4), *block = calloc(bound, 4),
           *buffer_block = calloc(bound, 4);
  for (size_t i = 5; i < word_count;) {
    uint32_t count = words[i] >> 16, op = words[i] & 0xffff;
    const uint32_t *a = &words[i + 1];
    if (count == 0) return 0;
    if (op == 17 && (a[0] == 5363 || a[0] == 5378)) out->fsi = 1;  // Fragment(Sample|Pixel)InterlockEXT
    if (op == 15 && a[0] == 4) out->fragment = 1;
    if (op == 71 && count >= 4 && a[0] < bound) {
      if (a[1] == 34) set_of[a[0]] = a[2], has_set[a[0]] = 1;
      if (a[1] == 33) binding_of[a[0]] = a[2];
    }
    if (op == 71 && count >= 3 && a[0] < bound && a[1] == 2) block[a[0]] = 1;
    if (op == 71 && count >= 3 && a[0] < bound && a[1] == 3) buffer_block[a[0]] = 1;
    if (((op >= 19 && op <= 32) || op == 43) && a[0] < bound && op != 43) {
      type_op[a[0]] = op;
      type_a[a[0]] = count > 2 ? a[1] : 0;
      type_b[a[0]] = count > 3 ? a[2] : 0;
      type_c[a[0]] = count > 4 ? a[3] : 0;
      type_d[a[0]] = count > 5 ? a[4] : 0;
      if (op == 25) type_c[a[0]] = a[4] /* arrayed */, type_d[a[0]] = a[2] /* dim */;
    }
    if (op == 59 && count >= 4) {
      uint32_t variable = a[1], storage = a[2], pointer = a[0];
      uint32_t pointee = type_op[pointer] == 32 ? type_b[pointer] : 0;
      if (storage == 9 && pointee) out->push_constant_bytes = 256;
      if (has_set[variable] && set_of[variable] < kMaxSets && binding_of[variable] < kMaxBindings && pointee) {
        Binding *binding = &out->bindings[set_of[variable]][binding_of[variable]];
        uint32_t element = pointee;
        if (type_op[element] == 28) element = type_a[element];  // descriptor array: count 1 assumed
        binding->used = 1;
        if (storage == 12 || (storage == 2 && buffer_block[element])) {
          binding->type = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
        } else if (storage == 2) {
          binding->type = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
        } else if (type_op[element] == 26) {
          binding->type = VK_DESCRIPTOR_TYPE_SAMPLER;
        } else if (type_op[element] == 25) {
          binding->type = VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE;
          uint32_t dim = type_d[element], arrayed = type_c[element];
          binding->view = dim == 1 ? (arrayed ? VK_IMAGE_VIEW_TYPE_2D_ARRAY : VK_IMAGE_VIEW_TYPE_2D)
                          : dim == 2 ? VK_IMAGE_VIEW_TYPE_3D
                          : dim == 3 ? (arrayed ? VK_IMAGE_VIEW_TYPE_CUBE_ARRAY : VK_IMAGE_VIEW_TYPE_CUBE)
                                     : VK_IMAGE_VIEW_TYPE_2D;
          uint32_t sampled = type_a[element];
          binding->integer = type_op[sampled] == 21 ? (type_b[sampled] ? 2 : 1) : 0;
          if (dim != 1 && dim != 2 && dim != 3) binding->used = 0;  // buffer / 1D: not in FSI shaders
        } else {
          binding->used = 0;
        }
      }
    }
    i += count;
  }
  free(set_of), free(binding_of), free(has_set), free(type_op), free(type_a), free(type_b), free(type_c);
  free(type_d), free(block), free(buffer_block);
  return 1;
}

typedef struct {
  VkImage image;
  VkDeviceMemory memory;
  VkImageView view;
} Texture;

static Texture texture_create(VkImageViewType view_type, VkFormat format) {
  Texture texture;
  uint32_t layers = (view_type == VK_IMAGE_VIEW_TYPE_CUBE) ? 6 : 1;
  VkImageCreateInfo info = {.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
                            .flags = view_type == VK_IMAGE_VIEW_TYPE_CUBE ? VK_IMAGE_CREATE_CUBE_COMPATIBLE_BIT : 0,
                            .imageType = view_type == VK_IMAGE_VIEW_TYPE_3D ? VK_IMAGE_TYPE_3D : VK_IMAGE_TYPE_2D,
                            .format = format,
                            .extent = {4, 4, 1},
                            .mipLevels = 1,
                            .arrayLayers = layers,
                            .samples = VK_SAMPLE_COUNT_1_BIT,
                            .tiling = VK_IMAGE_TILING_OPTIMAL,
                            .usage = VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT};
  CHECK(vkCreateImage(device, &info, NULL, &texture.image));
  VkMemoryRequirements requirements;
  vkGetImageMemoryRequirements(device, texture.image, &requirements);
  VkMemoryAllocateInfo allocate = {
      .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
      .allocationSize = requirements.size,
      .memoryTypeIndex = memory_type(requirements.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)};
  CHECK(vkAllocateMemory(device, &allocate, NULL, &texture.memory));
  CHECK(vkBindImageMemory(device, texture.image, texture.memory, 0));
  VkImageViewCreateInfo view = {.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
                                .image = texture.image,
                                .viewType = view_type,
                                .format = format,
                                .subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, layers}};
  CHECK(vkCreateImageView(device, &view, NULL, &texture.view));
  begin();
  VkImageMemoryBarrier to_transfer = {.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
                                      .dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT,
                                      .oldLayout = VK_IMAGE_LAYOUT_UNDEFINED,
                                      .newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                                      .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
                                      .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
                                      .image = texture.image,
                                      .subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, layers}};
  vkCmdPipelineBarrier(command, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, NULL, 0,
                       NULL, 1, &to_transfer);
  VkClearColorValue color = {.uint32 = {37, 101, 173, 211}};
  if (format == VK_FORMAT_R8G8B8A8_UNORM) color = (VkClearColorValue){.float32 = {0.25f, 0.5f, 0.75f, 1.0f}};
  vkCmdClearColorImage(command, texture.image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, &color, 1,
                       &to_transfer.subresourceRange);
  VkImageMemoryBarrier to_read = to_transfer;
  to_read.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
  to_read.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
  to_read.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
  to_read.newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
  vkCmdPipelineBarrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, 0, 0, NULL,
                       0, NULL, 1, &to_read);
  submit_and_wait("texture setup");
  return texture;
}

// Xenia's system constants (std140 offsets from the SPIR-V block):
// flags@0 edram_32bpp_tile_pitch_dwords_scaled@168 edram_depth_base@172
// alpha_to_mask@176 zpd_fsi_counter_index@180 color_exp_bias@192
// edram_rt_base_dwords_scaled@240 edram_rt_format_flags@256
// edram_rt_blend_factors_ops@272 edram_rt_keep_mask@288 edram_rt_clamp@320.
static int zpd_report;  // see zpd-count: count into slot 0 instead of the skip sentinel
static void fill_system_constants(uint32_t *words, uint32_t msaa_log2, int depth) {
  memset(words, 0, 1024);
  // MSAA in bits 8-9, alpha test "always" in 11-13, and for the depth run:
  // depth/stencil on (18), compare "always" (19-21) and depth write (22).
  words[0] = (msaa_log2 << 8) | (7u << 11) | (depth ? ((1u << 18) | (7u << 19) | (1u << 22)) : 0);
  // A 160x32 draw covers at most 4 x 4 tiles (4x MSAA doubles both axes), so
  // a 4-tile pitch and 16-tile spacing keep every surface's pixels apart:
  // overlapping surfaces would make different pixels race for one EDRAM word,
  // and interlock orders only fragments of the same pixel.
  words[168 / 4] = 1280 * 4;
  words[172 / 4] = 1280 * 64;
  words[180 / 4] = zpd_report ? 0u : 0xFFFFFFFFu;  // zpd_fsi_counter_index: UINT32_MAX skips counting
  float one = 1.0f;
  for (int i = 0; i < 4; i++) memcpy(&words[192 / 4 + i], &one, 4);
  for (int rt = 0; rt < 4; rt++) {
    words[240 / 4 + rt] = 1280u * 16u * (uint32_t)rt;  // render targets in separate EDRAM tiles
    words[272 / 4 + rt] = 0x00010001;                 // no blending
    float clamp_values[4] = {-65504.0f, -65504.0f, 65504.0f, 65504.0f};
    memcpy(&words[320 / 4 + rt * 4], clamp_values, 16);
  }
  // Stencil: always pass, keep everything; depth range of the test is unused.
  words[224 / 4] = 0xFF00FF00 | (7u << 0);
  words[232 / 4] = 0xFF00FF00 | (7u << 0);
}

// Deterministic xorshift, so a hostile run is reproducible.
static uint32_t hostile_state = 0x9E3779B9u;
static uint32_t hostile_next(void) {
  hostile_state ^= hostile_state << 13;
  hostile_state ^= hostile_state >> 17;
  hostile_state ^= hostile_state << 5;
  return hostile_state;
}

// Xenia's constant blocks sit 4 KiB apart in one allocation, binding b at
// 4096 * (b + 1): system constants (0), vertex and pixel float constants
// (1, 2), bool/loop constants (3), fetch constants (4).
//
// Sane: every Xenos loop runs twice from aL = 0 with step 1, so loop-relative
// constant reads stay inside the 256-entry block, and the original and
// hardened shaders must agree word for word. Hostile: every constant is
// random, including loop counts, starts and steps (aL-relative reads then
// reach far past the block, which faulted the GPU with an original shader)
// and the EDRAM bases, pitch and ZPD counter index.
static void fill_constants(Buffer *constants, uint32_t msaa_log2, int depth, int hostile) {
  for (uint32_t i = 0; i < 65536 / 4; i++) {
    if (hostile) {
      constants->words[i] = hostile_next();
    } else {
      float value = (float)(i % 61) * 0.125f;
      memcpy(&constants->words[i], &value, 4);
    }
  }
  uint32_t *system = &constants->words[4096 / 4];
  if (!hostile) {
    fill_system_constants(system, msaa_log2, depth);
    uint32_t *bool_loop = &constants->words[4096 * 4 / 4];
    for (int i = 0; i < 8; i++) bool_loop[i] = 0x55555555u;
    for (int i = 0; i < 32; i++) bool_loop[8 + i] = 2u | (0u << 8) | (1u << 16);
  } else {
    // Keep only the bits that select the sample count and depth path, so the
    // run exercises the configuration it names.
    system[0] = (system[0] & ~((3u << 8) | (1u << 18))) | (msaa_log2 << 8) | (depth ? (1u << 18) : 0);
    // Random loop starts and steps drive aL-relative reads far out of range;
    // the trip count stays at 1-4 so nested loops cannot turn a draw into a
    // multi-second GPU job (that would be a watchdog hang, not an access).
    uint32_t *loops = &constants->words[4096 * 4 / 4 + 8];
    for (int i = 0; i < 32; i++) loops[i] = (1u + hostile_next() % 4u) | (hostile_next() & 0x00FFFF00u);
  }
}

static int include_original_hostile;
// `zpd-count`: report the FSI occlusion counter the way Xenia drives it (stale
// contents, vkCmdFillBuffer, barrier, draw) and skip the hostile-constant runs.
static int zpd_only;

static int run_fsi_module(const char *name, const uint32_t *original, size_t original_size, const uint32_t *hardened,
                          size_t hardened_size, VkShaderModule vertex, VkRenderPass pass, VkFramebuffer framebuffer,
                          Buffer *edram, Buffer *shared, Buffer *zpd, Buffer *constants, Texture *textures,
                          VkSampler sampler, uint32_t width, uint32_t height, uint32_t msaa_log2, int depth,
                          uint32_t *snapshot) {
  const uint32_t edram_words = 2621440, guard_words = 16384, sentinel = 0xBADC0DE5;
  Reflection reflection;
  if (!reflect(original, original_size / 4, &reflection) || !reflection.fsi || !reflection.fragment) return -1;
  VkDescriptorSetLayout layouts[kMaxSets];
  for (uint32_t set = 0; set < kMaxSets; set++) {
    VkDescriptorSetLayoutBinding bindings[kMaxBindings];
    uint32_t count = 0;
    for (uint32_t binding = 0; binding < kMaxBindings; binding++) {
      Binding *b = &reflection.bindings[set][binding];
      if (!b->used) continue;
      bindings[count++] = (VkDescriptorSetLayoutBinding){.binding = binding,
                                                         .descriptorType = b->type,
                                                         .descriptorCount = 1,
                                                         .stageFlags = VK_SHADER_STAGE_ALL_GRAPHICS};
    }
    VkDescriptorSetLayoutCreateInfo info = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
                                            .bindingCount = count,
                                            .pBindings = bindings};
    CHECK(vkCreateDescriptorSetLayout(device, &info, NULL, &layouts[set]));
  }
  VkPushConstantRange push = {VK_SHADER_STAGE_ALL_GRAPHICS, 0, reflection.push_constant_bytes};
  VkPipelineLayoutCreateInfo layout_info = {.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
                                            .setLayoutCount = kMaxSets,
                                            .pSetLayouts = layouts,
                                            .pushConstantRangeCount = reflection.push_constant_bytes ? 1 : 0,
                                            .pPushConstantRanges = &push};
  VkPipelineLayout layout;
  CHECK(vkCreatePipelineLayout(device, &layout_info, NULL, &layout));
  VkDescriptorPool pool = make_pool();
  VkDescriptorSet sets[kMaxSets];
  for (uint32_t set = 0; set < kMaxSets; set++) {
    sets[set] = allocate_set(pool, layouts[set]);
    for (uint32_t binding = 0; binding < kMaxBindings; binding++) {
      Binding *b = &reflection.bindings[set][binding];
      if (!b->used) continue;
      if (b->type == VK_DESCRIPTOR_TYPE_STORAGE_BUFFER) {
        if (set == 0 && binding == 1)
          write_buffer(sets[set], binding, b->type, edram->buffer, 0, edram_words * 4ull);
        else if (set == 0 && binding == 2)
          write_buffer(sets[set], binding, b->type, zpd->buffer, 0, 32768);
        else
          write_buffer(sets[set], binding, b->type, shared->buffer, 0, 1u << 20);
      } else if (b->type == VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER) {
        // Xenia's constant blocks, each 4 KiB apart inside one allocation.
        write_buffer(sets[set], binding, b->type, constants->buffer, 4096ull * (binding + 1), 4096);
      } else {
        VkDescriptorImageInfo image = {.sampler = sampler, .imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL};
        if (b->type == VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE) {
          int index = b->view == VK_IMAGE_VIEW_TYPE_3D ? 2 : b->view == VK_IMAGE_VIEW_TYPE_CUBE ? 3
                      : b->view == VK_IMAGE_VIEW_TYPE_2D ? 1 : 0;
          if (b->integer) index = 4;
          image.imageView = textures[index].view;
        }
        VkWriteDescriptorSet write = {.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                                      .dstSet = sets[set],
                                      .dstBinding = binding,
                                      .descriptorCount = 1,
                                      .descriptorType = b->type,
                                      .pImageInfo = &image};
        vkUpdateDescriptorSets(device, 1, &write, 0, NULL);
      }
    }
  }
  fill_constants(constants, msaa_log2, depth, 0);
  int result = 0;
  // Three runs from the same initial EDRAM: the original twice (a control:
  // a shader whose output is not reproducible cannot be compared), then the
  // hardened module. Every word must match the first run.
  uint32_t *control = malloc(edram_words * 4ull);
  int reproducible = 1;
  for (int run = 0; run < 3 && !result; run++) {
    if (zpd_only && run != 2) continue;  // the counter is read from the production module only
    int hardened_run = run == 2;
    VkShaderModule fragment = hardened_run ? module_from_words(hardened, hardened_size)
                                           : module_from_words(original, original_size);
    VkPipeline pipeline;
    VkResult created = graphics_pipeline(pass, layout, vertex, fragment, (VkSampleCountFlagBits)(1u << msaa_log2),
                                         width, height, &pipeline);
    if (created != VK_SUCCESS) {
      printf("FAIL fsi-corpus %s %s: pipeline creation VkResult=%d\n", name, hardened_run ? "hardened" : "original",
             created);
      vkDestroyShaderModule(device, fragment, NULL);
      result = 1;
      break;
    }
    for (uint32_t i = 0; i < edram_words; i++) edram->words[i] = i * 2654435761u;
    for (uint32_t i = edram_words; i < edram_words + guard_words; i++) edram->words[i] = sentinel;
    begin();
    if (zpd_report) {
      // Xenia clears the slot it is about to count into, then relies on a
      // barrier so the pixel shader's atomics start from zero.
      memset(zpd->words, 0xEF, 32768);
      vkCmdFillBuffer(command, zpd->buffer, 0, 32768, 0);
      VkMemoryBarrier fill_done = {.sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER,
                                   .srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT,
                                   .dstAccessMask = VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_SHADER_WRITE_BIT};
      vkCmdPipelineBarrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, 0, 1,
                           &fill_done, 0, NULL, 0, NULL);
    }
    vkCmdBindPipeline(command, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);
    vkCmdBindDescriptorSets(command, VK_PIPELINE_BIND_POINT_GRAPHICS, layout, 0, kMaxSets, sets, 0, NULL);
    if (reflection.push_constant_bytes) {
      uint8_t zeros[256] = {0};
      vkCmdPushConstants(command, layout, VK_SHADER_STAGE_ALL_GRAPHICS, 0, reflection.push_constant_bytes, zeros);
    }
    VkRenderPassBeginInfo begin_pass = {.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
                                        .renderPass = pass,
                                        .framebuffer = framebuffer,
                                        .renderArea = {{0, 0}, {width, height}}};
    vkCmdBeginRenderPass(command, &begin_pass, VK_SUBPASS_CONTENTS_INLINE);
    vkCmdDraw(command, 3, 1, 0, 0);
    vkCmdEndRenderPass(command);
    submit_and_wait(name);
    if (zpd_report && run == 2) {
      uint32_t expected = width * height * (1u << msaa_log2);
      printf("ZPD %s msaa=%ux depth=%d counter=%u covered_samples=%u ratio=%.4f\n", name, 1u << msaa_log2, depth,
             zpd->words[0], expected, expected ? (double)zpd->words[0] / expected : 0.0);
    }
    if (zpd_only) {
      vkDestroyPipeline(device, pipeline, NULL);
      vkDestroyShaderModule(device, fragment, NULL);
      continue;
    }
    uint32_t guard_writes = sentinel_hits(edram->words, edram_words, guard_words, sentinel);
    if (guard_writes) {
      printf("FAIL fsi-corpus %s %s: %u words written past the EDRAM range\n", name,
             hardened_run ? "hardened" : "original", guard_writes);
      result = 1;
    }
    if (run == 0) {
      memcpy(snapshot, edram->words, edram_words * 4ull);
    } else if (run == 1) {
      memcpy(control, edram->words, edram_words * 4ull);
      reproducible = memcmp(snapshot, control, edram_words * 4ull) == 0;
    } else {
      size_t differing = 0, first = 0;
      uint32_t changed = 0;
      for (uint32_t i = 0; i < edram_words; i++) {
        if (snapshot[i] != edram->words[i] && (reproducible || control[i] == snapshot[i])) {
          if (!differing) first = i;
          differing++;
        }
        changed += snapshot[i] != i * 2654435761u;
      }
      if (differing) {
        printf("FAIL fsi-corpus %s msaa=%ux depth=%d: hardened EDRAM differs from original in %zu %sword(s) (first %zu)\n",
               name, 1u << msaa_log2, depth, differing, reproducible ? "" : "reproducible ", first);
        result = 1;
      } else {
        printf("PASS fsi-corpus %s msaa=%ux depth=%d: %s EDRAM, %u words written, guard intact\n", name,
               1u << msaa_log2, depth, reproducible ? "identical" : "identical where the original reproduces itself",
               changed);
      }
    }
    vkDestroyPipeline(device, pipeline, NULL);
    vkDestroyShaderModule(device, fragment, NULL);
  }
  free(control);
  // Hostile constants: the hardened module only, unless the caller asked to
  // watch an original shader fault.
  for (int run = 0; run < (include_original_hostile ? 2 : 1) && !result && !zpd_only; run++) {
    int hardened_run = run == 0;
    VkShaderModule fragment = hardened_run ? module_from_words(hardened, hardened_size)
                                           : module_from_words(original, original_size);
    VkPipeline pipeline;
    if (graphics_pipeline(pass, layout, vertex, fragment, (VkSampleCountFlagBits)(1u << msaa_log2), width, height,
                          &pipeline) != VK_SUCCESS) {
      printf("FAIL fsi-corpus %s hostile %s: pipeline creation failed\n", name, hardened_run ? "hardened" : "original");
      vkDestroyShaderModule(device, fragment, NULL);
      result = 1;
      break;
    }
    for (int round = 0; round < 3; round++) {
      fill_constants(constants, msaa_log2, depth, 1);
      for (uint32_t i = 0; i < edram_words; i++) edram->words[i] = i * 2654435761u;
      for (uint32_t i = edram_words; i < edram_words + guard_words; i++) edram->words[i] = sentinel;
      memset(zpd->words, 0, 32768);
      begin();
      vkCmdBindPipeline(command, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);
      vkCmdBindDescriptorSets(command, VK_PIPELINE_BIND_POINT_GRAPHICS, layout, 0, kMaxSets, sets, 0, NULL);
      if (reflection.push_constant_bytes) {
        uint8_t zeros[256] = {0};
        vkCmdPushConstants(command, layout, VK_SHADER_STAGE_ALL_GRAPHICS, 0, reflection.push_constant_bytes, zeros);
      }
      VkRenderPassBeginInfo begin_pass = {.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
                                          .renderPass = pass,
                                          .framebuffer = framebuffer,
                                          .renderArea = {{0, 0}, {width, height}}};
      vkCmdBeginRenderPass(command, &begin_pass, VK_SUBPASS_CONTENTS_INLINE);
      vkCmdDraw(command, 3, 1, 0, 0);
      vkCmdEndRenderPass(command);
      submit_and_wait(name);
      uint32_t guard_writes = sentinel_hits(edram->words, edram_words, guard_words, sentinel);
      if (guard_writes) {
        printf("FAIL fsi-corpus %s hostile %s round=%d: %u words written past the EDRAM range\n", name,
               hardened_run ? "hardened" : "original", round, guard_writes);
        result = 1;
      }
    }
    if (!result) {
      printf("PASS fsi-corpus %s msaa=%ux depth=%d hostile %s: 3 random-constant draws completed, guard intact\n", name,
             1u << msaa_log2, depth, hardened_run ? "hardened" : "original");
    }
    vkDestroyPipeline(device, pipeline, NULL);
    vkDestroyShaderModule(device, fragment, NULL);
  }
  vkDestroyDescriptorPool(device, pool, NULL);
  vkDestroyPipelineLayout(device, layout, NULL);
  for (uint32_t set = 0; set < kMaxSets; set++) vkDestroyDescriptorSetLayout(device, layouts[set], NULL);
  return result;
}

static int fsi_corpus(const char *original_dir, const char *hardened_dir, const char *vertex_path) {
  const uint32_t edram_words = 2621440, guard_words = 16384, width = 160, height = 32;
  Buffer edram = buffer_create((edram_words + guard_words) * 4ull, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);
  Buffer shared = buffer_create(1u << 20, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);
  Buffer zpd = buffer_create(32768, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT);
  Buffer constants = buffer_create(65536, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);
  for (uint32_t i = 0; i < (1u << 18); i++) shared.words[i] = i;
  memset(zpd.words, 0, 32768);
  for (uint32_t i = 0; i < 65536 / 4; i++) {
    float value = (float)(i % 61) * 0.125f;
    memcpy(&constants.words[i], &value, 4);
  }
  Texture textures[5] = {texture_create(VK_IMAGE_VIEW_TYPE_2D_ARRAY, VK_FORMAT_R8G8B8A8_UNORM),
                         texture_create(VK_IMAGE_VIEW_TYPE_2D, VK_FORMAT_R8G8B8A8_UNORM),
                         texture_create(VK_IMAGE_VIEW_TYPE_3D, VK_FORMAT_R8G8B8A8_UNORM),
                         texture_create(VK_IMAGE_VIEW_TYPE_CUBE, VK_FORMAT_R8G8B8A8_UNORM),
                         texture_create(VK_IMAGE_VIEW_TYPE_2D, VK_FORMAT_R8G8B8A8_UINT)};
  VkSamplerCreateInfo sampler_info = {.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
                                      .magFilter = VK_FILTER_NEAREST,
                                      .minFilter = VK_FILTER_NEAREST,
                                      .addressModeU = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
                                      .addressModeV = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
                                      .addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
                                      .maxLod = 0};
  VkSampler sampler;
  CHECK(vkCreateSampler(device, &sampler_info, NULL, &sampler));
  VkRenderPass pass = fsi_render_pass();
  VkFramebuffer framebuffer = fsi_framebuffer(pass, width, height);
  size_t vertex_size;
  uint32_t *vertex_words = read_file(vertex_path, &vertex_size);
  if (!vertex_words) exit(2);
  VkShaderModule vertex = module_from_words(vertex_words, vertex_size);
  uint32_t *snapshot = malloc(edram_words * 4ull);
  DIR *dir = opendir(original_dir);
  if (!dir) exit(2);
  struct dirent *entry;
  int modules = 0, bad = 0, skipped = 0;
  while ((entry = readdir(dir))) {
    size_t length = strlen(entry->d_name);
    if (length < 5 || strcmp(entry->d_name + length - 4, ".spv")) continue;
    char path[4096];
    snprintf(path, sizeof(path), "%s/%s", original_dir, entry->d_name);
    size_t original_size, hardened_size;
    uint32_t *original = read_file(path, &original_size);
    snprintf(path, sizeof(path), "%s/%s", hardened_dir, entry->d_name);
    uint32_t *hardened = read_file(path, &hardened_size);
    if (!original || !hardened) {
      free(original), free(hardened);
      continue;
    }
    Reflection reflection;
    if (!reflect(original, original_size / 4, &reflection) || !reflection.fsi || !reflection.fragment) {
      skipped++;
      free(original), free(hardened);
      continue;
    }
    modules++;
    // 1x without depth, 4x with depth and stencil: both of Xenia's EDRAM
    // layouts, through the shaders' own sample-offset arithmetic.
    bad += run_fsi_module(entry->d_name, original, original_size, hardened, hardened_size, vertex, pass, framebuffer,
                          &edram, &shared, &zpd, &constants, textures, sampler, width, height, 0, 0, snapshot) != 0;
    bad += run_fsi_module(entry->d_name, original, original_size, hardened, hardened_size, vertex, pass, framebuffer,
                          &edram, &shared, &zpd, &constants, textures, sampler, width, height, 2, 1, snapshot) != 0;
    free(original), free(hardened);
  }
  closedir(dir);
  printf("fsi-corpus: modules=%d runs=%d failed_runs=%d non_fsi_skipped=%d\n", modules, modules * 2, bad, skipped);
  free(snapshot);
  free(vertex_words);
  return bad;
}

int main(int argc, char **argv) {
  if (argc >= 4 && !strcmp(argv[1], "patterns")) {
    create_device(argv[2]);
    pattern_dir = argv[3];
    pattern_vertex_fetch();
    pattern_relative_constant(0);
    pattern_export_store();
    pattern_interlocked_store();
  } else if (argc == 4 && !strcmp(argv[1], "uniform-zero")) {
    // Safe regression: only the hardened compute module is ever dispatched.
    create_device(argv[2]);
    pattern_dir = argv[3];
    pattern_relative_constant(1);
  } else if (argc == 4 && !strcmp(argv[1], "color-math")) {
    // Bounded synthetic operations only; no game shaders or hostile accesses.
    create_device(argv[2]);
    pattern_dir = argv[3];
    pattern_color_math();
  } else if (argc == 6 && !strcmp(argv[1], "zpd-count")) {
    // Real Xenia FSI shaders, original modules only, counter reported per run.
    zpd_report = 1;
    zpd_only = 1;
    create_device(argv[2]);
    failures += fsi_corpus(argv[3], argv[4], argv[5]);
  } else if (argc >= 6 && !strcmp(argv[1], "fsi-corpus")) {
    // Opt-in only: an original Xenia shader with random loop constants can
    // fault the GPU (it did, natively, during this probe's development).
    include_original_hostile = argc >= 7 && !strcmp(argv[6], "--include-original-hostile");
    create_device(argv[2]);
    failures += fsi_corpus(argv[3], argv[4], argv[5]);
  } else {
    fprintf(stderr,
            "usage: probe patterns DRIVER.dylib DIR\n"
            "       probe uniform-zero DRIVER.dylib DIR (hardened module only)\n"
            "       probe color-math DRIVER.dylib DIR (bounded synthetic HDR conversion)\n"
            "       probe fsi-corpus DRIVER.dylib ORIGINAL_DIR HARDENED_DIR VERTEX.spv [--include-original-hostile]\n"
            "       probe zpd-count DRIVER.dylib ORIGINAL_DIR HARDENED_DIR VERTEX.spv (FSI occlusion counter per shader)\n");
    return 2;
  }
  CHECK(vkDeviceWaitIdle(device));
  printf("%s: %d failure(s)\n", failures ? "FAILED" : "PASSED", failures);
  return failures ? 1 : 0;
}
