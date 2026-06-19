#include <stdio.h>
#include <stdlib.h>

extern int rosette_mscoree_show_managed_window(void);

int main(int argc, char **argv)
{
    if (argc > 1) setenv("ROSETTE_EXE_PATH", argv[1], 1);
    if (argc > 2) setenv("ROSETTE_TRACE_PATH", argv[2], 1);
    if (argc > 3) setenv("ROSETTE_MANAGED_WINDOW_AUTOCLOSE_MS", argv[3], 1);
    setenv("ROSETTE_MANAGED_GUI", "1", 1);
    return rosette_mscoree_show_managed_window();
}
