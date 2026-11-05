#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <string.h>

static uint32_t rd32(const uint8_t *p) { uint32_t v; memcpy(&v, p, 4); return v; }
static uint64_t rd64(const uint8_t *p) { uint64_t v; memcpy(&v, p, 8); return v; }

__attribute__((constructor))
static void dumpbox_main(void) {
    @autoreleasepool {
        NSBundle *bundle = [NSBundle mainBundle];
        NSString *bid = [bundle bundleIdentifier];
        if (!bid.length) return;

        NSString *exePath = [bundle executablePath];
        if (!exePath) return;

        const struct mach_header_64 *hdr = NULL;
        uint32_t imgCount = _dyld_image_count();
        for (uint32_t i = 0; i < imgCount; i++) {
            const char *name = _dyld_get_image_name(i);
            if (name && strcmp(name, exePath.fileSystemRepresentation) == 0) {
                hdr = (const struct mach_header_64 *)_dyld_get_image_header(i);
                break;
            }
        }
        if (!hdr) return;
        if (hdr->magic != MH_MAGIC_64) return;

        const uint8_t *base = (const uint8_t *)hdr;
        const uint8_t *p = base + sizeof(struct mach_header_64);
        uint64_t textOff = 0, textSize = 0;
        uint32_t cryptCmdOff = 0;
        BOOL hasCrypt = NO;

        for (uint32_t i = 0; i < hdr->ncmds; i++) {
            uint32_t cmd = rd32(p);
            uint32_t cmdsize = rd32(p + 4);
            if (cmdsize < 8) break;
            if (cmd == LC_SEGMENT_64) {
                if (strncmp((const char *)(p + 8), "__TEXT", 16) == 0) {
                    textOff = rd64(p + 40);
                    textSize = rd64(p + 48);
                }
            } else if (cmd == LC_ENCRYPTION_INFO_64) {
                cryptCmdOff = (uint32_t)(p - base);
                hasCrypt = YES;
            }
            p += cmdsize;
        }
        if (textSize == 0) return;

        NSData *disk = [NSData dataWithContentsOfFile:exePath];
        if (!disk) return;

        NSMutableData *out = [disk mutableCopy];
        if (textOff + textSize > out.length) return;

        [out replaceBytesInRange:NSMakeRange(textOff, textSize) withBytes:base];

        if (hasCrypt) {
            uint32_t zero = 0;
            [out replaceBytesInRange:NSMakeRange(cryptCmdOff + 16, 4) withBytes:&zero];
        }

        NSArray *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        if (docs.count == 0) return;
        NSString *outPath = [docs.firstObject stringByAppendingPathComponent:
                             [NSString stringWithFormat:@"%@_dump", bid]];
        [out writeToFile:outPath atomically:YES];
    }
}
