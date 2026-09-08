pub const dos = struct {
    pub const signature = 0x5A4D;
};

pub const coff = struct {
    pub const signature = 0x00004550;
    pub const machine_i386: u16 = 0x014c;
    pub const machine_amd64: u16 = 0x8664;
    pub const optional_magic_pe32: u16 = 0x010b;
    pub const optional_magic_pe32_plus: u16 = 0x020b;

    // Subsystem values
    pub const subsystem_windows_gui: u16 = 2;
    pub const subsystem_windows_cui: u16 = 3;
};

pub const data_dir = struct {
    pub const entry_import: usize = 1;
    pub const entry_resource: usize = 2;
    pub const entry_exception: usize = 3;
    pub const entry_security: usize = 4;
    pub const entry_basereloc: usize = 5;
    pub const entry_debug: usize = 6;
};

pub const opt32 = struct {
    pub const minimum_size: u16 = 96;
    pub const number_of_rva_and_sizes_off: u16 = 92;
    pub const data_dir_off: u16 = 96;
};

pub const opt64 = struct {
    pub const minimum_size: u16 = 112;
    pub const number_of_rva_and_sizes_off: u16 = 108;
    pub const data_dir_off: u16 = 112;
};

pub const import = struct {
    pub const descriptor_size: u16 = 20;
    pub const ordinal_flag32: u32 = 0x80000000;
    pub const ordinal_flag64: u64 = 0x8000000000000000;
};
