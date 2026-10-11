// Which triangle edge does each gl_TessLevelOuter drive on this driver?
//
// Vulkan: outer[0] is the edge where u = 0, outer[1] where v = 0, outer[2]
// where w = 0 (gl_TessCoord = (u, v, w)). Xenia's adaptive tessellation (Halo 3
// water) assigns a different factor to each edge and relies on that mapping;
// a driver that maps the levels to other edges gives two patches sharing an
// edge different subdivisions of it, which cracks along every patch edge.
//
//   probe_tess_edges DRIVER.dylib SHADER_DIR
//
// One patch, rasterizer discard, the evaluation shader records each domain
// point; the CPU counts distinct points with u, v or w exactly zero. With equal
// spacing an edge of level N carries N + 1 points. No game shader runs.
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define VK_NO_PROTOTYPES
#include <vulkan/vulkan.h>

#define FUNCTIONS(X)                                                                         \
  X(CreateInstance) X(EnumeratePhysicalDevices) X(GetPhysicalDeviceMemoryProperties)         \
  X(GetPhysicalDeviceFeatures) X(CreateDevice) X(GetDeviceQueue) X(CreateBuffer)             \
  X(GetBufferMemoryRequirements) X(AllocateMemory) X(BindBufferMemory) X(MapMemory)          \
  X(CreateDescriptorSetLayout) X(CreatePipelineLayout) X(CreateDescriptorPool)               \
  X(AllocateDescriptorSets) X(UpdateDescriptorSets) X(CreateShaderModule)                    \
  X(CreateGraphicsPipelines) X(CreateRenderPass) X(CreateFramebuffer) X(CreateCommandPool)   \
  X(AllocateCommandBuffers) X(BeginCommandBuffer) X(EndCommandBuffer) X(CmdBeginRenderPass)  \
  X(CmdEndRenderPass) X(CmdBindPipeline) X(CmdBindDescriptorSets) X(CmdPushConstants)        \
  X(CmdDraw) X(QueueSubmit) X(CreateFence) X(WaitForFences) X(ResetFences)                    \
  X(ResetCommandBuffer)
#define DECLARE(n) static PFN_vk##n vk##n;
FUNCTIONS(DECLARE)

#define CHECK(e)                                                   \
  do {                                                             \
    VkResult r_ = (e);                                             \
    if (r_ != VK_SUCCESS) {                                        \
      fprintf(stderr, "%s failed: %d\n", #e, r_);                  \
      exit(2);                                                     \
    }                                                              \
  } while (0)

static VkShaderModule load(VkDevice device, const char *dir, const char *name) {
  char path[1024];
  snprintf(path, sizeof path, "%s/%s", dir, name);
  FILE *file = fopen(path, "rb");
  if (!file) {
    fprintf(stderr, "missing %s\n", path);
    exit(2);
  }
  fseek(file, 0, SEEK_END);
  long bytes = ftell(file);
  fseek(file, 0, SEEK_SET);
  uint32_t *code = malloc((size_t)bytes);
  if (fread(code, 1, (size_t)bytes, file) != (size_t)bytes) exit(2);
  fclose(file);
  VkShaderModuleCreateInfo info = {.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
                                   .codeSize = (size_t)bytes, .pCode = code};
  VkShaderModule module;
  CHECK(vkCreateShaderModule(device, &info, NULL, &module));
  return module;
}

static int distinct_on_edge(const float *points, uint32_t count, int axis) {
  int found = 0;
  for (uint32_t i = 0; i < count; i++) {
    const float *p = points + 4 * i;
    if (p[axis] != 0.0f) continue;
    int seen = 0;
    for (uint32_t j = 0; j < i; j++) {
      const float *q = points + 4 * j;
      if (q[axis] == 0.0f && q[0] == p[0] && q[1] == p[1] && q[2] == p[2]) {
        seen = 1;
        break;
      }
    }
    if (!seen) found++;
  }
  return found;
}

int main(int argc, char **argv) {
  if (argc != 3) {
    fprintf(stderr, "usage: probe_tess_edges DRIVER.dylib SHADER_DIR\n");
    return 2;
  }
  setenv("MVK_CONFIG_FAST_MATH_ENABLED", "0", 1);
  void *library = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
  if (!library) return 2;
#define LOAD(n)                                       \
  vk##n = (PFN_vk##n)dlsym(library, "vk" #n);         \
  if (!vk##n) return 2;
  FUNCTIONS(LOAD)
  VkApplicationInfo app = {.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO, .apiVersion = VK_API_VERSION_1_2};
  VkInstanceCreateInfo instance_info = {.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, .pApplicationInfo = &app};
  VkInstance instance;
  CHECK(vkCreateInstance(&instance_info, NULL, &instance));
  uint32_t count = 1;
  VkPhysicalDevice physical;
  CHECK(vkEnumeratePhysicalDevices(instance, &count, &physical));
  VkPhysicalDeviceFeatures supported;
  vkGetPhysicalDeviceFeatures(physical, &supported);
  if (!supported.tessellationShader || !supported.vertexPipelineStoresAndAtomics) {
    fprintf(stderr, "tessellation or vertex-pipeline stores unsupported\n");
    return 2;
  }
  VkPhysicalDeviceMemoryProperties memory;
  vkGetPhysicalDeviceMemoryProperties(physical, &memory);
  float priority = 1;
  VkDeviceQueueCreateInfo queue_info = {.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
                                        .queueFamilyIndex = 0, .queueCount = 1, .pQueuePriorities = &priority};
  VkPhysicalDeviceFeatures features = {.tessellationShader = VK_TRUE, .vertexPipelineStoresAndAtomics = VK_TRUE};
  const char *extensions[] = {"VK_KHR_portability_subset"};
  VkDeviceCreateInfo device_info = {.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO, .queueCreateInfoCount = 1,
                                    .pQueueCreateInfos = &queue_info, .enabledExtensionCount = 1,
                                    .ppEnabledExtensionNames = extensions, .pEnabledFeatures = &features};
  VkDevice device;
  CHECK(vkCreateDevice(physical, &device_info, NULL, &device));
  VkQueue queue;
  vkGetDeviceQueue(device, 0, 0, &queue);

  const VkDeviceSize size = 16 + 4096 * 16;
  VkBufferCreateInfo buffer_info = {.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO, .size = size,
                                    .usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT};
  VkBuffer buffer;
  CHECK(vkCreateBuffer(device, &buffer_info, NULL, &buffer));
  VkMemoryRequirements requirements;
  vkGetBufferMemoryRequirements(device, buffer, &requirements);
  uint32_t type = UINT32_MAX;
  const VkMemoryPropertyFlags wanted = VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
  for (uint32_t i = 0; i < memory.memoryTypeCount; i++)
    if ((requirements.memoryTypeBits & (1u << i)) && (memory.memoryTypes[i].propertyFlags & wanted) == wanted) {
      type = i;
      break;
    }
  VkMemoryAllocateInfo allocate = {.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
                                   .allocationSize = requirements.size, .memoryTypeIndex = type};
  VkDeviceMemory device_memory;
  CHECK(vkAllocateMemory(device, &allocate, NULL, &device_memory));
  CHECK(vkBindBufferMemory(device, buffer, device_memory, 0));
  uint32_t *data;
  CHECK(vkMapMemory(device, device_memory, 0, size, 0, (void **)&data));

  VkDescriptorSetLayoutBinding binding = {.binding = 0, .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
                                          .descriptorCount = 1, .stageFlags = VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT};
  VkDescriptorSetLayoutCreateInfo set_layout_info = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
                                                     .bindingCount = 1, .pBindings = &binding};
  VkDescriptorSetLayout set_layout;
  CHECK(vkCreateDescriptorSetLayout(device, &set_layout_info, NULL, &set_layout));
  VkPushConstantRange push = {.stageFlags = VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT, .offset = 0, .size = 16};
  VkPipelineLayoutCreateInfo layout_info = {.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
                                            .setLayoutCount = 1, .pSetLayouts = &set_layout,
                                            .pushConstantRangeCount = 1, .pPushConstantRanges = &push};
  VkPipelineLayout layout;
  CHECK(vkCreatePipelineLayout(device, &layout_info, NULL, &layout));

  VkSubpassDescription subpass = {.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS};
  VkRenderPassCreateInfo pass_info = {.sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO, .subpassCount = 1, .pSubpasses = &subpass};
  VkRenderPass pass;
  CHECK(vkCreateRenderPass(device, &pass_info, NULL, &pass));
  VkFramebufferCreateInfo framebuffer_info = {.sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO, .renderPass = pass,
                                              .width = 16, .height = 16, .layers = 1};
  VkFramebuffer framebuffer;
  CHECK(vkCreateFramebuffer(device, &framebuffer_info, NULL, &framebuffer));

  VkPipelineShaderStageCreateInfo stages[4] = {
      {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, .stage = VK_SHADER_STAGE_VERTEX_BIT,
       .module = load(device, argv[2], "tess_edges.vert.spv"), .pName = "main"},
      {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, .stage = VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT,
       .module = load(device, argv[2], "tess_edges.tesc.spv"), .pName = "main"},
      {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, .stage = VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT,
       .module = load(device, argv[2], "tess_edges.tese.spv"), .pName = "main"},
      {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, .stage = VK_SHADER_STAGE_FRAGMENT_BIT,
       .module = load(device, argv[2], "tess_edges.frag.spv"), .pName = "main"}};
  VkPipelineVertexInputStateCreateInfo vertex_input = {.sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO};
  VkPipelineInputAssemblyStateCreateInfo assembly = {.sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
                                                     .topology = VK_PRIMITIVE_TOPOLOGY_PATCH_LIST};
  VkPipelineTessellationStateCreateInfo tessellation = {.sType = VK_STRUCTURE_TYPE_PIPELINE_TESSELLATION_STATE_CREATE_INFO,
                                                        .patchControlPoints = 3};
  VkViewport viewport = {0, 0, 16, 16, 0, 1};
  VkRect2D scissor = {{0, 0}, {16, 16}};
  VkPipelineViewportStateCreateInfo viewport_state = {.sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
                                                      .viewportCount = 1, .pViewports = &viewport, .scissorCount = 1, .pScissors = &scissor};
  VkPipelineRasterizationStateCreateInfo raster = {.sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
                                                   .rasterizerDiscardEnable = VK_TRUE, .lineWidth = 1};
  VkPipelineMultisampleStateCreateInfo multisample = {.sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
                                                      .rasterizationSamples = VK_SAMPLE_COUNT_1_BIT};
  VkPipelineColorBlendStateCreateInfo blend = {.sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO};
  VkGraphicsPipelineCreateInfo pipeline_info = {.sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO, .stageCount = 4,
                                                .pStages = stages, .pVertexInputState = &vertex_input, .pInputAssemblyState = &assembly,
                                                .pTessellationState = &tessellation, .pViewportState = &viewport_state,
                                                .pRasterizationState = &raster, .pMultisampleState = &multisample,
                                                .pColorBlendState = &blend, .layout = layout, .renderPass = pass};
  VkPipeline pipeline;
  CHECK(vkCreateGraphicsPipelines(device, VK_NULL_HANDLE, 1, &pipeline_info, NULL, &pipeline));

  VkDescriptorPoolSize pool_size = {.type = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .descriptorCount = 1};
  VkDescriptorPoolCreateInfo pool_info = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO, .maxSets = 1,
                                          .poolSizeCount = 1, .pPoolSizes = &pool_size};
  VkDescriptorPool pool;
  CHECK(vkCreateDescriptorPool(device, &pool_info, NULL, &pool));
  VkDescriptorSetAllocateInfo set_info = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO, .descriptorPool = pool,
                                          .descriptorSetCount = 1, .pSetLayouts = &set_layout};
  VkDescriptorSet set;
  CHECK(vkAllocateDescriptorSets(device, &set_info, &set));
  VkDescriptorBufferInfo descriptor = {.buffer = buffer, .offset = 0, .range = size};
  VkWriteDescriptorSet write = {.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = set, .descriptorCount = 1,
                                .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .pBufferInfo = &descriptor};
  vkUpdateDescriptorSets(device, 1, &write, 0, NULL);

  VkCommandPoolCreateInfo command_pool_info = {.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
                                               .flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT, .queueFamilyIndex = 0};
  VkCommandPool command_pool;
  CHECK(vkCreateCommandPool(device, &command_pool_info, NULL, &command_pool));
  VkCommandBufferAllocateInfo command_info = {.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO, .commandPool = command_pool,
                                              .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY, .commandBufferCount = 1};
  VkCommandBuffer command;
  CHECK(vkAllocateCommandBuffers(device, &command_info, &command));
  VkFenceCreateInfo fence_info = {.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO};
  VkFence fence;
  CHECK(vkCreateFence(device, &fence_info, NULL, &fence));

  static const float cases[][4] = {{2, 5, 9, 0}, {9, 2, 5, 0}, {5, 9, 2, 0}};
  int failures = 0;
  for (int c = 0; c < 3; c++) {
    memset(data, 0, (size_t)size);
    CHECK(vkResetCommandBuffer(command, 0));
    VkCommandBufferBeginInfo begin = {.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
    CHECK(vkBeginCommandBuffer(command, &begin));
    VkRenderPassBeginInfo pass_begin = {.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO, .renderPass = pass,
                                        .framebuffer = framebuffer, .renderArea = {{0, 0}, {16, 16}}};
    vkCmdBeginRenderPass(command, &pass_begin, VK_SUBPASS_CONTENTS_INLINE);
    vkCmdBindPipeline(command, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);
    vkCmdBindDescriptorSets(command, VK_PIPELINE_BIND_POINT_GRAPHICS, layout, 0, 1, &set, 0, NULL);
    vkCmdPushConstants(command, layout, VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT, 0, 16, cases[c]);
    vkCmdDraw(command, 3, 1, 0, 0);
    vkCmdEndRenderPass(command);
    CHECK(vkEndCommandBuffer(command));
    VkSubmitInfo submit = {.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO, .commandBufferCount = 1, .pCommandBuffers = &command};
    CHECK(vkResetFences(device, 1, &fence));
    CHECK(vkQueueSubmit(queue, 1, &submit, fence));
    CHECK(vkWaitForFences(device, 1, &fence, VK_TRUE, 10000000000ull));
    uint32_t points = data[0] < 4096 ? data[0] : 4096;
    const float *coords = (const float *)(data + 4);
    int edges[3];
    for (int axis = 0; axis < 3; axis++) edges[axis] = distinct_on_edge(coords, points, axis) - 1;
    int ok = edges[0] == (int)cases[c][0] && edges[1] == (int)cases[c][1] && edges[2] == (int)cases[c][2];
    failures += !ok;
    printf("%s outer=(%g,%g,%g) segments on u=0/v=0/w=0 edges = %d/%d/%d (invocations %u)\n", ok ? "PASS" : "FAIL",
           cases[c][0], cases[c][1], cases[c][2], edges[0], edges[1], edges[2], data[0]);
  }
  printf("%s: outer levels map to the Vulkan edges\n", failures ? "MISMATCH" : "OK");
  return failures ? 1 : 0;
}
