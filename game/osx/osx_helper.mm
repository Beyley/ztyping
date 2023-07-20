#include "osx_helper.h"

#include <Foundation/Foundation.h>
#include <QuartzCore/CAMetalLayer.h>
#include <AppKit/AppKit.h>

extern "C" {

CAMetalLayer *createMetalLayer(NSWindow *ns_window)
{
    id metal_layer = NULL;
    [ns_window.contentView setWantsLayer:YES];
    metal_layer = [CAMetalLayer layer];
    [ns_window.contentView setLayer:metal_layer];
    return metal_layer;
}

}