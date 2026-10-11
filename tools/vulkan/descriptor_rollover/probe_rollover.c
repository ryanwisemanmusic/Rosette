// Does the driver apply one VkWriteDescriptorSet that rolls over consecutive
// bindings? Vulkan: when descriptorCount exceeds the elements left in
// dstBinding, the rest update dstBinding + 1 from element 0, and so on.
// Xenia writes every draw's textures this way (dstBinding 0, descriptorCount N
// over N single-descriptor bindings). A driver that only updates the first
// binding leaves the other slots holding whatever an earlier draw put there.
//
//   probe_rollover DRIVER.dylib SHADER_DIR
//
// Bindings 0..3 first get "old" resources one by one, then one rolled-over
// write of four "new" ones; a compute dispatch reports what each binding
// holds. Sampled images (Xenia's case) and storage buffers are both checked.
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define VK_NO_PROTOTYPES
#include <vulkan/vulkan.h>

#define FUNCTIONS(X)                                                                         \
  X(CreateInstance) X(EnumeratePhysicalDevices) X(GetPhysicalDeviceMemoryProperties)         \
  X(CreateDevice) X(GetDeviceQueue) X(CreateBuffer) X(GetBufferMemoryRequirements)           \
  X(AllocateMemory) X(BindBufferMemory) X(MapMemory) X(CreateImage) X(GetImageMemoryRequirements) \
  X(BindImageMemory) X(CreateImageView) X(CreateDescriptorSetLayout) X(CreatePipelineLayout) \
  X(CreateDescriptorPool) X(AllocateDescriptorSets) X(UpdateDescriptorSets) X(CreateShaderModule) \
  X(CreateComputePipelines) X(CreateCommandPool) X(AllocateCommandBuffers) X(BeginCommandBuffer) \
  X(EndCommandBuffer) X(CmdBindPipeline) X(CmdBindDescriptorSets) X(CmdDispatch)             \
  X(CmdPipelineBarrier) X(CmdClearColorImage) X(QueueSubmit) X(CreateFence) X(WaitForFences) \
  X(ResetFences) X(ResetCommandBuffer)
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

static VkDevice device;
static VkPhysicalDeviceMemoryProperties memory;
static VkQueue queue;
static VkCommandBuffer command;
static VkFence fence;

static uint32_t memory_type(uint32_t bits, VkMemoryPropertyFlags wanted) {
  for (uint32_t i = 0; i < memory.memoryTypeCount; i++)
    if ((bits & (1u << i)) && (memory.memoryTypes[i].propertyFlags & wanted) == wanted) return i;
  exit(2);
}

static VkBuffer make_buffer(VkDeviceSize size, uint32_t **mapped) {
  VkBufferCreateInfo info = {.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO, .size = size,
                             .usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT};
  VkBuffer buffer;
  CHECK(vkCreateBuffer(device, &info, NULL, &buffer));
  VkMemoryRequirements req;
  vkGetBufferMemoryRequirements(device, buffer, &req);
  VkMemoryAllocateInfo alloc = {.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, .allocationSize = req.size,
                                .memoryTypeIndex = memory_type(req.memoryTypeBits, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)};
  VkDeviceMemory mem;
  CHECK(vkAllocateMemory(device, &alloc, NULL, &mem));
  CHECK(vkBindBufferMemory(device, buffer, mem, 0));
  CHECK(vkMapMemory(device, mem, 0, size, 0, (void **)mapped));
  return buffer;
}

static VkImage make_image(VkImageView *view) {
  VkImageCreateInfo info = {.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO, .imageType = VK_IMAGE_TYPE_2D,
                            .format = VK_FORMAT_R8G8B8A8_UNORM, .extent = {1, 1, 1}, .mipLevels = 1, .arrayLayers = 1,
                            .samples = VK_SAMPLE_COUNT_1_BIT, .tiling = VK_IMAGE_TILING_OPTIMAL,
                            .usage = VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT};
  VkImage image;
  CHECK(vkCreateImage(device, &info, NULL, &image));
  VkMemoryRequirements req;
  vkGetImageMemoryRequirements(device, image, &req);
  VkMemoryAllocateInfo alloc = {.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, .allocationSize = req.size,
                                .memoryTypeIndex = memory_type(req.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)};
  VkDeviceMemory mem;
  CHECK(vkAllocateMemory(device, &alloc, NULL, &mem));
  CHECK(vkBindImageMemory(device, image, mem, 0));
  VkImageViewCreateInfo view_info = {.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO, .image = image,
                                     .viewType = VK_IMAGE_VIEW_TYPE_2D, .format = VK_FORMAT_R8G8B8A8_UNORM,
                                     .subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1}};
  CHECK(vkCreateImageView(device, &view_info, NULL, view));
  return image;
}

static VkPipeline make_pipeline(const char *dir, const char *name, VkDescriptorType type, VkDescriptorSetLayout *set_layout, VkPipelineLayout *layout) {
  VkDescriptorSetLayoutBinding bindings[5];
  for (uint32_t i = 0; i < 5; i++)
    bindings[i] = (VkDescriptorSetLayoutBinding){.binding = i, .descriptorType = i < 4 ? type : VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
                                                 .descriptorCount = 1, .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT};
  VkDescriptorSetLayoutCreateInfo set_info = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO, .bindingCount = 5, .pBindings = bindings};
  CHECK(vkCreateDescriptorSetLayout(device, &set_info, NULL, set_layout));
  VkPipelineLayoutCreateInfo layout_info = {.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO, .setLayoutCount = 1, .pSetLayouts = set_layout};
  CHECK(vkCreatePipelineLayout(device, &layout_info, NULL, layout));
  char path[1024];
  snprintf(path, sizeof path, "%s/%s", dir, name);
  FILE *file = fopen(path, "rb");
  if (!file) exit(2);
  fseek(file, 0, SEEK_END);
  long bytes = ftell(file);
  fseek(file, 0, SEEK_SET);
  uint32_t *code = malloc((size_t)bytes);
  if (fread(code, 1, (size_t)bytes, file) != (size_t)bytes) exit(2);
  fclose(file);
  VkShaderModuleCreateInfo module_info = {.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO, .codeSize = (size_t)bytes, .pCode = code};
  VkShaderModule module;
  CHECK(vkCreateShaderModule(device, &module_info, NULL, &module));
  VkComputePipelineCreateInfo info = {.sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
                                      .stage = {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, .stage = VK_SHADER_STAGE_COMPUTE_BIT, .module = module, .pName = "main"},
                                      .layout = *layout};
  VkPipeline pipeline;
  CHECK(vkCreateComputePipelines(device, VK_NULL_HANDLE, 1, &info, NULL, &pipeline));
  return pipeline;
}

static void run(VkPipeline pipeline, VkPipelineLayout layout, VkDescriptorSet set, VkImage *clear, int clear_count) {
  CHECK(vkResetCommandBuffer(command, 0));
  VkCommandBufferBeginInfo begin = {.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
  CHECK(vkBeginCommandBuffer(command, &begin));
  for (int i = 0; i < clear_count; i++) {
    VkImageMemoryBarrier to_dst = {.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER, .dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT,
                                   .oldLayout = VK_IMAGE_LAYOUT_UNDEFINED, .newLayout = VK_IMAGE_LAYOUT_GENERAL,
                                   .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED, .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
                                   .image = clear[i], .subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1}};
    vkCmdPipelineBarrier(command, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, NULL, 0, NULL, 1, &to_dst);
    VkClearColorValue color = {.float32 = {(float)(i + 1) / 8.0f, 0, 0, 1}};
    VkImageSubresourceRange range = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
    vkCmdClearColorImage(command, clear[i], VK_IMAGE_LAYOUT_GENERAL, &color, 1, &range);
    VkImageMemoryBarrier to_read = to_dst;
    to_read.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
    to_read.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
    to_read.oldLayout = VK_IMAGE_LAYOUT_GENERAL;
    vkCmdPipelineBarrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0, 0, NULL, 0, NULL, 1, &to_read);
  }
  vkCmdBindPipeline(command, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
  vkCmdBindDescriptorSets(command, VK_PIPELINE_BIND_POINT_COMPUTE, layout, 0, 1, &set, 0, NULL);
  vkCmdDispatch(command, 1, 1, 1);
  CHECK(vkEndCommandBuffer(command));
  VkSubmitInfo submit = {.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO, .commandBufferCount = 1, .pCommandBuffers = &command};
  CHECK(vkResetFences(device, 1, &fence));
  CHECK(vkQueueSubmit(queue, 1, &submit, fence));
  CHECK(vkWaitForFences(device, 1, &fence, VK_TRUE, 10000000000ull));
}

int main(int argc, char **argv) {
  if (argc != 3) return 2;
  void *library = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
  if (!library) return 2;
#define LOAD(n)                               \
  vk##n = (PFN_vk##n)dlsym(library, "vk" #n); \
  if (!vk##n) return 2;
  FUNCTIONS(LOAD)
  VkApplicationInfo app = {.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO, .apiVersion = VK_API_VERSION_1_2};
  VkInstanceCreateInfo instance_info = {.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, .pApplicationInfo = &app};
  VkInstance instance;
  CHECK(vkCreateInstance(&instance_info, NULL, &instance));
  uint32_t count = 1;
  VkPhysicalDevice physical;
  CHECK(vkEnumeratePhysicalDevices(instance, &count, &physical));
  vkGetPhysicalDeviceMemoryProperties(physical, &memory);
  float priority = 1;
  VkDeviceQueueCreateInfo queue_info = {.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, .queueFamilyIndex = 0, .queueCount = 1, .pQueuePriorities = &priority};
  const char *extensions[] = {"VK_KHR_portability_subset"};
  VkDeviceCreateInfo device_info = {.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO, .queueCreateInfoCount = 1, .pQueueCreateInfos = &queue_info,
                                    .enabledExtensionCount = 1, .ppEnabledExtensionNames = extensions};
  CHECK(vkCreateDevice(physical, &device_info, NULL, &device));
  vkGetDeviceQueue(device, 0, 0, &queue);
  VkCommandPoolCreateInfo pool_info = {.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO, .flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT, .queueFamilyIndex = 0};
  VkCommandPool command_pool;
  CHECK(vkCreateCommandPool(device, &pool_info, NULL, &command_pool));
  VkCommandBufferAllocateInfo command_info = {.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO, .commandPool = command_pool, .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY, .commandBufferCount = 1};
  CHECK(vkAllocateCommandBuffers(device, &command_info, &command));
  VkFenceCreateInfo fence_info = {.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO};
  CHECK(vkCreateFence(device, &fence_info, NULL, &fence));
  VkDescriptorPoolSize sizes[2] = {{VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 16}, {VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE, 16}};
  VkDescriptorPoolCreateInfo dpool_info = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO, .maxSets = 4, .poolSizeCount = 2, .pPoolSizes = sizes};
  VkDescriptorPool dpool;
  CHECK(vkCreateDescriptorPool(device, &dpool_info, NULL, &dpool));
  int failures = 0;

  // Storage buffers.
  {
    VkDescriptorSetLayout set_layout;
    VkPipelineLayout layout;
    VkPipeline pipeline = make_pipeline(argv[2], "rollover.spv", VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, &set_layout, &layout);
    VkDescriptorSetAllocateInfo alloc = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO, .descriptorPool = dpool, .descriptorSetCount = 1, .pSetLayouts = &set_layout};
    VkDescriptorSet set;
    CHECK(vkAllocateDescriptorSets(device, &alloc, &set));
    VkBuffer buffers[9];
    uint32_t *mapped[9];
    for (int i = 0; i < 9; i++) {
      buffers[i] = make_buffer(256, &mapped[i]);
      mapped[i][0] = 100 + (uint32_t)i;  // 100..103 old, 104..107 new, 108 output
    }
    VkDescriptorBufferInfo infos[9];
    for (int i = 0; i < 9; i++) infos[i] = (VkDescriptorBufferInfo){buffers[i], 0, 256};
    VkWriteDescriptorSet singles[5];
    for (uint32_t b = 0; b < 5; b++)
      singles[b] = (VkWriteDescriptorSet){.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = set, .dstBinding = b, .descriptorCount = 1,
                                          .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .pBufferInfo = &infos[b < 4 ? b : 8]};
    vkUpdateDescriptorSets(device, 5, singles, 0, NULL);
    VkWriteDescriptorSet roll = {.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = set, .dstBinding = 0, .descriptorCount = 4,
                                 .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .pBufferInfo = &infos[4]};
    vkUpdateDescriptorSets(device, 1, &roll, 0, NULL);
    run(pipeline, layout, set, NULL, 0);
    int ok = 1;
    for (int b = 0; b < 4; b++) ok &= mapped[8][b] == 104u + (uint32_t)b;
    failures += !ok;
    printf("%s storage buffers: bindings hold %u %u %u %u (new = 104 105 106 107, old = 100..103)\n", ok ? "PASS" : "FAIL",
           mapped[8][0], mapped[8][1], mapped[8][2], mapped[8][3]);
  }
  // Sampled images, Xenia's case.
  {
    VkDescriptorSetLayout set_layout;
    VkPipelineLayout layout;
    VkPipeline pipeline = make_pipeline(argv[2], "rollover_image.spv", VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE, &set_layout, &layout);
    VkDescriptorSetAllocateInfo alloc = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO, .descriptorPool = dpool, .descriptorSetCount = 1, .pSetLayouts = &set_layout};
    VkDescriptorSet set;
    CHECK(vkAllocateDescriptorSets(device, &alloc, &set));
    VkImage images[8];
    VkImageView views[8];
    for (int i = 0; i < 8; i++) images[i] = make_image(&views[i]);
    uint32_t *out;
    VkBuffer output = make_buffer(256, &out);
    VkDescriptorImageInfo infos[8];
    for (int i = 0; i < 8; i++) infos[i] = (VkDescriptorImageInfo){VK_NULL_HANDLE, views[i], VK_IMAGE_LAYOUT_GENERAL};
    VkDescriptorBufferInfo out_info = {output, 0, 256};
    VkWriteDescriptorSet singles[5];
    for (uint32_t b = 0; b < 4; b++)
      singles[b] = (VkWriteDescriptorSet){.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = set, .dstBinding = b, .descriptorCount = 1,
                                          .descriptorType = VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE, .pImageInfo = &infos[b]};
    singles[4] = (VkWriteDescriptorSet){.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = set, .dstBinding = 4, .descriptorCount = 1,
                                        .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .pBufferInfo = &out_info};
    vkUpdateDescriptorSets(device, 5, singles, 0, NULL);
    VkWriteDescriptorSet roll = {.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = set, .dstBinding = 0, .descriptorCount = 4,
                                 .descriptorType = VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE, .pImageInfo = &infos[4]};
    vkUpdateDescriptorSets(device, 1, &roll, 0, NULL);
    run(pipeline, layout, set, images, 8);
    const float *v = (const float *)out;
    int ok = 1;
    int held[4];
    for (int b = 0; b < 4; b++) {
      held[b] = (int)(v[4 * b] * 8.0f + 0.5f) - 1;  // image index from its clear colour
      ok &= held[b] == 4 + b;
    }
    failures += !ok;
    printf("%s sampled images: bindings hold images %d %d %d %d (new = 4 5 6 7, old = 0..3)\n", ok ? "PASS" : "FAIL", held[0], held[1], held[2], held[3]);
  }
  printf("%s\n", failures ? "ROLLOVER NOT APPLIED" : "rollover applied");
  return failures ? 1 : 0;
}
