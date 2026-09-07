/*
 * The Windows SDK/PIX header is not shipped by MinGW-w64. The Xenia
 * sources only include it for optional programmable-capture declarations;
 * this external build supplies the interface shape without a PIX dependency.
 */
#ifndef XENIA_CANARY_DX_PROGRAMMABLE_CAPTURE_COMPAT_H_
#define XENIA_CANARY_DX_PROGRAMMABLE_CAPTURE_COMPAT_H_

#include <unknwn.h>

struct __declspec(uuid("00000000-0000-0000-0000-000000000001"))
    IDXGraphicsAnalysis : public IUnknown {
  virtual HRESULT STDMETHODCALLTYPE BeginCapture() = 0;
  virtual HRESULT STDMETHODCALLTYPE EndCapture() = 0;
};

#endif
