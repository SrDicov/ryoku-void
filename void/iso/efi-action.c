typedef unsigned long long uint64_t;
typedef unsigned int uint32_t;
typedef unsigned long long uintn_t;
typedef uint64_t efi_status_t;
typedef void *efi_handle_t;

#ifndef RYOKU_RESET_TYPE
#error RYOKU_RESET_TYPE is required
#endif

#define EFIAPI __attribute__((ms_abi))

struct efi_table_header {
	uint64_t signature;
	uint32_t revision;
	uint32_t header_size;
	uint32_t crc32;
	uint32_t reserved;
};

struct efi_runtime_services {
	struct efi_table_header header;
	void *get_time;
	void *set_time;
	void *get_wakeup_time;
	void *set_wakeup_time;
	void *set_virtual_address_map;
	void *convert_pointer;
	void *get_variable;
	void *get_next_variable_name;
	void *set_variable;
	void *get_next_high_monotonic_count;
	void (EFIAPI *reset_system)(uint32_t, efi_status_t, uintn_t, void *);
};

struct efi_system_table {
	struct efi_table_header header;
	unsigned short *firmware_vendor;
	uint32_t firmware_revision;
	efi_handle_t console_in_handle;
	void *con_in;
	efi_handle_t console_out_handle;
	void *con_out;
	efi_handle_t standard_error_handle;
	void *std_err;
	struct efi_runtime_services *runtime_services;
	void *boot_services;
	uintn_t number_of_table_entries;
	void *configuration_table;
};

efi_status_t EFIAPI efi_main(efi_handle_t image, struct efi_system_table *system_table) {
	(void)image;
	system_table->runtime_services->reset_system(RYOKU_RESET_TYPE, 0, 0, (void *)0);
	for (;;) __asm__ volatile ("hlt");
}
