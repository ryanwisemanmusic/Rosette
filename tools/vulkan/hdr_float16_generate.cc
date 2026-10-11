// Offline harness for the exact, read-only Xenia extended-float16 functions.
// hdr_production.inc is generated from two source function extents by the
// checker, not a maintained fork. No guest or graphics device is created here.
#include <cstdlib>
#include <fstream>
#include "xenia/gpu/spirv_builder.h"
#include "xenia/gpu/spirv_compatibility.h"
#include "third_party/glslang/SPIRV/GLSL.std.450.h"

namespace xe::gpu {
class SpirvShaderTranslator {
 public:
  SpirvBuilder* builder_;
  spv::Id type_float_, type_float2_, type_uint_, type_bool_, type_bool2_;
  spv::Id ext_inst_glsl_std_450_, const_float2_0_, const_uint_0_;
  std::vector<spv::Id> id_vector_temp_;
  explicit SpirvShaderTranslator(SpirvBuilder& b) : builder_(&b) {
    type_float_=b.makeFloatType(32); type_float2_=b.makeVectorType(type_float_,2);
    type_uint_=b.makeUintType(32); type_bool_=b.makeBoolType();
    type_bool2_=b.makeVectorType(type_bool_,2);
    ext_inst_glsl_std_450_=b.import("GLSL.std.450");
    const_uint_0_=b.makeUintConstant(0);
    const_float2_0_=b.makeCompositeConstant(type_float2_,{b.makeFloatConstant(0),b.makeFloatConstant(0)});
  }
  spv::Id PackFloat16x2ExtendedRange(spv::Id);
  spv::Id UnpackFloat16x2ExtendedRange(spv::Id);
};
#include "hdr_production.inc"
}

int main(int argc,char** argv) {
  if(argc!=3)return 2;
  unsigned rows=std::strtoul(argv[2],nullptr,10); if(!rows || rows>131072)return 2;
  using namespace xe::gpu;
  spv::SpvBuildLogger logger;
  SpirvBuilder b(0x00010500,0,&logger);
  b.addCapability(spv::CapabilityShader);
  b.setMemoryModel(spv::AddressingModelLogical,spv::MemoryModelGLSL450);
  SpirvShaderTranslator t(b);
  const auto u=t.type_uint_, u3=b.makeVectorType(u,3), u4=b.makeVectorType(u,4);
  auto array=b.makeRuntimeArray(u4); b.addDecoration(array,spv::DecorationArrayStride,16);
  auto block=b.makeStructType({array},"Rows");
  b.addDecoration(block,spv::DecorationBlock);
  b.addMemberDecoration(block,0,spv::DecorationOffset,0);
  auto input=b.createVariable(spv::NoPrecision,spv::StorageClassStorageBuffer,block,"input",0);
  auto output=b.createVariable(spv::NoPrecision,spv::StorageClassStorageBuffer,block,"output",0);
  b.addDecoration(input,spv::DecorationDescriptorSet,0); b.addDecoration(input,spv::DecorationBinding,0);
  b.addDecoration(output,spv::DecorationDescriptorSet,0); b.addDecoration(output,spv::DecorationBinding,1);
  auto invocation=b.createVariable(spv::NoPrecision,spv::StorageClassInput,u3,"id",0);
  b.addDecoration(invocation,spv::DecorationBuiltIn,static_cast<unsigned>(spv::BuiltIn::GlobalInvocationId));
  spv::Block* main_block=nullptr;
  auto main=b.makeFunctionEntry(spv::NoPrecision,b.makeVoidType(),"main",{}, {}, &main_block);
  auto entry=b.addEntryPoint(spv::ExecutionModelGLCompute,main,"main");
  entry->addIdOperand(input);entry->addIdOperand(output);entry->addIdOperand(invocation);
  b.addExecutionMode(main,spv::ExecutionModeLocalSize,64,1,1);
  auto index=b.createCompositeExtract(b.createLoad(invocation,spv::NoPrecision),u,0);
  SpirvBuilder::IfBuilder within(b.createBinOp(spv::OpULessThan,t.type_bool_,index,b.makeUintConstant(rows)),spv::SelectionControlMaskNone,b);
  auto row=b.createLoad(b.createAccessChain(spv::StorageClassStorageBuffer,input,{t.const_uint_0_,index}),spv::NoPrecision);
  auto decoded=t.UnpackFloat16x2ExtendedRange(b.createCompositeExtract(row,u,0));
  auto x=b.createUnaryOp(spv::OpBitcast,t.type_float_,b.createCompositeExtract(row,u,1));
  auto y=b.createUnaryOp(spv::OpBitcast,t.type_float_,b.createCompositeExtract(row,u,2));
  auto packed=t.PackFloat16x2ExtendedRange(b.createCompositeConstruct(t.type_float2_,{x,y}));
  auto roundtrip=t.PackFloat16x2ExtendedRange(decoded);
  auto decoded_bits=b.createUnaryOp(spv::OpBitcast,b.makeVectorType(u,2),decoded);
  auto result=b.createCompositeConstruct(u4,{b.createCompositeExtract(decoded_bits,u,0),b.createCompositeExtract(decoded_bits,u,1),packed,roundtrip});
  b.createStore(result,b.createAccessChain(spv::StorageClassStorageBuffer,output,{t.const_uint_0_,index}));
  within.makeEndIf();b.makeReturn(false);b.leaveFunction();
  std::vector<unsigned> words;b.dump(words);
  std::ofstream f(argv[1],std::ios::binary);f.write(reinterpret_cast<char*>(words.data()),words.size()*4);
  return f?0:3;
}
