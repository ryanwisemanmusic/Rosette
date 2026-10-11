// Safe synthetic inputs only: native MSL inside the existing Vulkan stream.
// The included harness's hostile/game modes are never called by this main.
#define main rosette_unused_robust_probe_main
#include "../vulkan/robust_access/probe.c"
#undef main

static VkPipeline native_pipeline(VkPipelineLayout layout, VkShaderModule module, const char* name) {
  VkComputePipelineCreateInfo pi={.sType=VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
    .stage={.sType=VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,.stage=VK_SHADER_STAGE_COMPUTE_BIT,.module=module,.pName=name},.layout=layout};
  VkPipeline p;CHECK(vkCreateComputePipelines(device,0,1,&pi,NULL,&p));return p;
}
static VkShaderModule from_file(const char* path, int msl) {
  FILE* f=fopen(path,"rb");if(!f)exit(2);fseek(f,0,SEEK_END);long n=ftell(f);rewind(f);
  if(n<=0||n>(16<<20))exit(2);uint32_t* b=calloc(1,(size_t)n+8);if(!b)exit(2);
  if(msl)b[0]=0x19960412;
  if(fread((char*)b+(msl?4:0),1,(size_t)n,f)!=(size_t)n)exit(2);fclose(f);
  VkShaderModule m=module_from_words(b,(size_t)n+(msl?5:0));free(b);return m;
}
static void barrier(VkAccessFlags src,VkAccessFlags dst) {
  VkMemoryBarrier b={.sType=VK_STRUCTURE_TYPE_MEMORY_BARRIER,.srcAccessMask=src,.dstAccessMask=dst};
  vkCmdPipelineBarrier(command,VK_PIPELINE_STAGE_ALL_COMMANDS_BIT,VK_PIPELINE_STAGE_ALL_COMMANDS_BIT,0,1,&b,0,NULL,0,NULL);
}
static int guards(Buffer b, uint32_t bytes) {
  const unsigned char* p=(const unsigned char*)b.words;
  for(uint32_t i=0;i<256;i++)if(p[i]!=0xa7||p[256+bytes+i]!=0xa7)return 0;return 1;
}
int main(int argc,char** argv) {
  if(argc<5)return 2;create_device(argv[1]);
  void* library=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);
  typedef void (*SetWorkgroup)(VkShaderModule,uint32_t,uint32_t,uint32_t);
  SetWorkgroup set=(SetWorkgroup)dlsym(library,"vkSetWorkgroupSizeMVK");if(!set)return 2;
  PFN_vkCmdCopyBuffer copy=(PFN_vkCmdCopyBuffer)dlsym(library,"vkCmdCopyBuffer");if(!copy)return 2;
  VkPhysicalDeviceProperties properties;vkGetPhysicalDeviceProperties(physical,&properties);
  if(properties.driverVersion!=10207||properties.limits.minStorageBufferOffsetAlignment>256)return 2;
  typedef VkResult (*Config)(VkInstance,void*,size_t*);
  Config config=(Config)dlsym(library,"vkGetMoltenVKConfigurationMVK");
  unsigned char conf[160]={0};size_t conf_size=160;
  if(!config||config(instance,conf,&conf_size)!=VK_SUCCESS||conf_size!=160||*(uint32_t*)(conf+144)!=0)return 2;
  VkShaderModule native=from_file(argv[2],1);set(native,4,32,1);
  VkDescriptorSetLayout layouts[4];
  for(int i=0;i<4;i++) {VkDescriptorType type=i<2?VK_DESCRIPTOR_TYPE_STORAGE_BUFFER:VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;layouts[i]=set_layout(&type,1,VK_SHADER_STAGE_COMPUTE_BIT);}
  VkPushConstantRange push={VK_SHADER_STAGE_COMPUTE_BIT,0,40};
  VkPipelineLayoutCreateInfo li={.sType=VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,.setLayoutCount=2,.pSetLayouts=layouts,.pushConstantRangeCount=1,.pPushConstantRanges=&push};
  VkPipelineLayout original_layout,live_layout;CHECK(vkCreatePipelineLayout(device,&li,NULL,&original_layout));li.setLayoutCount=4;CHECK(vkCreatePipelineLayout(device,&li,NULL,&live_layout));
  const char* names[]={"ctx1","dxt1_rgba8","dxt3_rgba8","dxt5_rgba8"};
  const char* entries[]={"rosette_live_ctx1","rosette_live_dxt1","rosette_live_dxt3","rosette_live_dxt5"};
  VkPipeline live[4],original[4];VkShaderModule modules[4];
  for(int i=0;i<4;i++) {char p[4096];snprintf(p,sizeof(p),"%s/%s.original.spv",argv[3],names[i]);modules[i]=from_file(p,0);original[i]=compute_pipeline(original_layout,modules[i]);live[i]=native_pipeline(live_layout,native,entries[i]);}
  VkDescriptorPool pool=make_pool();VkDescriptorSet sets[4];for(int i=0;i<4;i++)sets[i]=allocate_set(pool,layouts[i]);
  Buffer source=buffer_create(2<<20,VK_BUFFER_USAGE_STORAGE_BUFFER_BIT), dest=buffer_create(2<<20,VK_BUFFER_USAGE_STORAGE_BUFFER_BIT|VK_BUFFER_USAGE_TRANSFER_SRC_BIT), reference=buffer_create(2<<20,VK_BUFFER_USAGE_STORAGE_BUFFER_BIT), copied=buffer_create(2<<20,VK_BUFFER_USAGE_TRANSFER_DST_BIT);
  VkDeviceSize alignment=properties.limits.minUniformBufferOffsetAlignment;if(alignment<16)alignment=16;
  Buffer bounds=buffer_create(alignment+16,VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);
  write_buffer(sets[2],0,VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,bounds.buffer,0,16);write_buffer(sets[3],0,VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,bounds.buffer,alignment,16);
  int count=0;
  for(int c=4;c<argc;c++) {
    FILE* f=fopen(argv[c],"rb");if(!f)return 2;uint32_t h[16];if(fread(h,sizeof(h),1,f)!=1)return 2;
    const uint32_t kind=h[0],compare=h[1],src_size=h[2],dst_size=h[3],src_range=h[4],dst_range=h[5];uint32_t* p=h+6;
    if(kind>3||src_size+512>(2<<20)||dst_size+512>(2<<20)||!src_range||!dst_range||src_range>src_size||dst_range>dst_size)return 2;
    unsigned char* input=malloc(src_size),*expected=malloc(dst_size),*mask=malloc(dst_size);if(!input||!expected||!mask)return 2;
    if(fread(input,src_size,1,f)!=1||fread(expected,dst_size,1,f)!=1||fread(mask,dst_size,1,f)!=1||fgetc(f)!=EOF)return 2;fclose(f);
    memset(source.words,0xa7,source.size);memcpy((char*)source.words+256,input,src_size);memset(dest.words,0xa7,dest.size);memset(reference.words,0xa7,reference.size);memset(copied.words,0xa7,copied.size);
    // Start with deliberately short VALID ranges, then legally update both the
    // descriptor and its bound UBO after recording and before submission.
    write_buffer(sets[0],0,VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,dest.buffer,256,4);write_buffer(sets[1],0,VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,source.buffer,256,4);
    bounds.words[0]=4;*(uint32_t*)((char*)bounds.words+alignment)=4;
    begin();vkCmdBindPipeline(command,VK_PIPELINE_BIND_POINT_COMPUTE,original[kind]);
    vkCmdBindDescriptorSets(command,VK_PIPELINE_BIND_POINT_COMPUTE,original_layout,0,2,sets,0,NULL);
    vkCmdPushConstants(command,original_layout,VK_SHADER_STAGE_COMPUTE_BIT,0,40,p);
    vkCmdBindPipeline(command,VK_PIPELINE_BIND_POINT_COMPUTE,live[kind]);vkCmdBindDescriptorSets(command,VK_PIPELINE_BIND_POINT_COMPUTE,live_layout,2,2,sets+2,0,NULL);
    vkCmdDispatch(command,(p[4]+15)/16,(p[5]+31)/32,1);
    vkCmdBindPipeline(command,VK_PIPELINE_BIND_POINT_COMPUTE,original[kind]);
    barrier(VK_ACCESS_SHADER_WRITE_BIT,VK_ACCESS_TRANSFER_READ_BIT);
    VkBufferCopy region={.srcOffset=256,.dstOffset=256,.size=dst_size};copy(command,dest.buffer,copied.buffer,1,&region);
    write_buffer(sets[0],0,VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,dest.buffer,256,dst_range);write_buffer(sets[1],0,VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,source.buffer,256,src_range);
    bounds.words[0]=dst_range;*(uint32_t*)((char*)bounds.words+alignment)=src_range;
    barrier(VK_ACCESS_TRANSFER_WRITE_BIT,VK_ACCESS_HOST_READ_BIT);
    submit_and_wait("native live texture");
    int ok=memcmp((char*)dest.words+256,expected,dst_size)==0&&memcmp((char*)copied.words+256,expected,dst_size)==0&&guards(dest,dst_size)&&guards(copied,dst_size)&&guards(source,src_size)&&memcmp((char*)source.words+256,input,src_size)==0;
    if(compare) {
      write_buffer(sets[0],0,VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,reference.buffer,256,dst_range);
      // Binding/push compatibility also checked in a mixed native/original
      // sequence: encode an isolated native dispatch, restore original PSO,
      // then issue an original dispatch without rebinding constants/sets.
      // Use separate commands here to keep oracle output independent.
      begin();vkCmdBindPipeline(command,VK_PIPELINE_BIND_POINT_COMPUTE,live[kind]);vkCmdBindDescriptorSets(command,VK_PIPELINE_BIND_POINT_COMPUTE,original_layout,0,2,sets,0,NULL);vkCmdBindDescriptorSets(command,VK_PIPELINE_BIND_POINT_COMPUTE,live_layout,2,2,sets+2,0,NULL);vkCmdPushConstants(command,original_layout,VK_SHADER_STAGE_COMPUTE_BIT,0,40,p);
      vkCmdDispatch(command,(p[4]+15)/16,(p[5]+31)/32,1);barrier(VK_ACCESS_SHADER_WRITE_BIT,VK_ACCESS_SHADER_READ_BIT|VK_ACCESS_SHADER_WRITE_BIT);
      vkCmdBindPipeline(command,VK_PIPELINE_BIND_POINT_COMPUTE,original[kind]);vkCmdDispatch(command,(p[4]+15)/16,(p[5]+31)/32,1);submit_and_wait("restored original loader");
      for(uint32_t i=0;i<dst_size;i++)if(mask[i]&&((unsigned char*)reference.words)[256+i]!=expected[i]){if(ok)printf("first original mismatch byte=%u actual=%u expected=%u\n",i,((unsigned char*)reference.words)[256+i],expected[i]);ok=0;break;}
      ok=ok&&guards(reference,dst_size);
    }
    EXPECT(ok,"%s native pixels/guards/Vulkan-copy/late-descriptors%s",argv[c],compare?"/restored-loader":"/bounded-only");
    free(input);free(expected);free(mask);count++;if(!ok)exit(1);
  }
  CHECK(vkDeviceWaitIdle(device));printf("TOTAL %d/%d synthetic live texture groups passed\n",count-failures,count);
  vkDestroyDescriptorPool(device,pool,NULL);
  Buffer buffers[]={source,dest,reference,copied,bounds};for(int i=0;i<5;i++){vkDestroyBuffer(device,buffers[i].buffer,NULL);vkFreeMemory(device,buffers[i].memory,NULL);}
  for(int i=0;i<4;i++){vkDestroyPipeline(device,live[i],NULL);vkDestroyPipeline(device,original[i],NULL);vkDestroyShaderModule(device,modules[i],NULL);vkDestroyDescriptorSetLayout(device,layouts[i],NULL);}vkDestroyShaderModule(device,native,NULL);vkDestroyPipelineLayout(device,live_layout,NULL);vkDestroyPipelineLayout(device,original_layout,NULL);vkDestroyFence(device,fence,NULL);vkDestroyCommandPool(device,command_pool,NULL);vkDestroyDevice(device,NULL);vkDestroyInstance(instance,NULL);return 0;
}
