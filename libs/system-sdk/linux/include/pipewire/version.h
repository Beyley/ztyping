/* PipeWire */
/* SPDX-FileCopyrightText: Copyright © 2018 Wim Taymans */
/* SPDX-License-Identifier: MIT */

#ifndef PIPEWIRE_VERSION_H
#define PIPEWIRE_VERSION_H

/* WARNING: Make sure to edit the real source file version.h.in! */

#ifdef __cplusplus
extern "C" {
#endif

/** Return the version of the header files. Keep in mind that this is
a macro and not a function, so it is impossible to get the pointer of
it. */
#define pw_get_headers_version() ("0.3.71")

/** Return the version of the library the current application is
 * linked to. */
const char* pw_get_library_version(void);

/** The current API version. Versions prior to 0.2.0 have
 * PW_API_VERSION undefined. Please note that this is only ever
 * increased on incompatible API changes!  */
#define PW_API_VERSION "0.3"

/** The major version of PipeWire. \since 0.2.0 */
#define PW_MAJOR 0

/** The minor version of PipeWire. \since 0.2.0 */
#define PW_MINOR 3

/** The micro version of PipeWire. \since 0.2.0 */
#define PW_MICRO 71

/** Evaluates to TRUE if the PipeWire library version is equal or
 * newer than the specified. \since 0.2.0 */
#define PW_CHECK_VERSION(major,minor,micro)                             \
    ((PW_MAJOR > (major)) ||                                            \
     (PW_MAJOR == (major) && PW_MINOR > (minor)) ||                     \
     (PW_MAJOR == (major) && PW_MINOR == (minor) && PW_MICRO >= (micro)))

#ifdef __cplusplus
}
#endif

#endif /* PIPEWIRE_VERSION_H */
