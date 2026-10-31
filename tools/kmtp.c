// kmtp: keep one MTP session open and run commands read line-by-line from stdin.
// Paths are resolved by name on every command (object IDs are not stable across sessions).
// Commands:
//   ls  <path>                 list children
//   tree <path>                recursive listing
//   get <path> <localpath>     download file or folder (recursive)
//   rm  <path>                 delete a FILE (refuses folders)
//   put <localfile> <dirpath>  upload file into dir (name = basename of local)
//   rmrf <path>                delete file or folder recursively (needs a "/" in path)
//   quit
#include <libmtp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <libgen.h>

static LIBMTP_mtpdevice_t *dev;
static uint32_t storage;

static LIBMTP_file_t *children(uint32_t parent) {
  return LIBMTP_Get_Files_And_Folders(dev, storage, parent);
}

static void free_list(LIBMTP_file_t *f) {
  while (f) { LIBMTP_file_t *n = f->next; LIBMTP_destroy_file_t(f); f = n; }
}

// Resolve path like "koreader/patches/x.lua". Returns 0 on success.
static int resolve(const char *path, uint32_t *id, int *is_folder, uint64_t *size) {
  uint32_t cur = LIBMTP_FILES_AND_FOLDERS_ROOT;
  int folder = 1; uint64_t sz = 0;
  char buf[4096]; strncpy(buf, path, sizeof buf - 1); buf[sizeof buf - 1] = 0;
  char *save = NULL;
  for (char *tok = strtok_r(buf, "/", &save); tok; tok = strtok_r(NULL, "/", &save)) {
    if (!folder) return -1;
    LIBMTP_file_t *list = children(cur), *f; int found = 0;
    for (f = list; f; f = f->next) {
      if (strcmp(f->filename, tok) == 0) {
        cur = f->item_id; folder = (f->filetype == LIBMTP_FILETYPE_FOLDER); sz = f->filesize; found = 1; break;
      }
    }
    free_list(list);
    if (!found) return -1;
  }
  *id = cur; *is_folder = folder; if (size) *size = sz;
  return 0;
}

static void tree(uint32_t parent, const char *prefix, int recursive) {
  LIBMTP_file_t *list = children(parent), *f;
  for (f = list; f; f = f->next) {
    int d = f->filetype == LIBMTP_FILETYPE_FOLDER;
    printf("%s%s%s\t%llu\n", prefix, f->filename, d ? "/" : "", (unsigned long long)f->filesize);
    if (d && recursive) {
      char p[4096]; snprintf(p, sizeof p, "%s%s/", prefix, f->filename);
      tree(f->item_id, p, 1);
    }
  }
  free_list(list);
}

static int get_rec(uint32_t id, int folder, const char *local) {
  if (!folder) {
    int r = LIBMTP_Get_File_To_File(dev, id, local, NULL, NULL);
    printf("%s %s\n", r ? "ERR" : "got", local);
    if (r) LIBMTP_Dump_Errorstack(dev), LIBMTP_Clear_Errorstack(dev);
    return r;
  }
  mkdir(local, 0755);
  int err = 0;
  LIBMTP_file_t *list = children(id), *f;
  for (f = list; f; f = f->next) {
    char p[4096]; snprintf(p, sizeof p, "%s/%s", local, f->filename);
    err |= get_rec(f->item_id, f->filetype == LIBMTP_FILETYPE_FOLDER, p);
  }
  free_list(list);
  return err;
}

// Recursive delete (children first). Returns 0 on success.
static int rm_rec(uint32_t id, int folder, const char *label) {
  if (folder) {
    LIBMTP_file_t *list = children(id), *f; int err = 0;
    for (f = list; f; f = f->next) {
      char p[4096]; snprintf(p, sizeof p, "%s/%s", label, f->filename);
      err |= rm_rec(f->item_id, f->filetype == LIBMTP_FILETYPE_FOLDER, p);
    }
    free_list(list);
    if (err) return err;
  }
  int r = LIBMTP_Delete_Object(dev, id);
  printf("%s del %s\n", r ? "ERR" : "ok", label);
  if (r) LIBMTP_Dump_Errorstack(dev), LIBMTP_Clear_Errorstack(dev);
  return r;
}

int main(void) {
  LIBMTP_Init();
  LIBMTP_raw_device_t *raw; int n;
  if (LIBMTP_Detect_Raw_Devices(&raw, &n) || n < 1) { printf("NODEVICE\n"); return 1; }
  dev = LIBMTP_Open_Raw_Device_Uncached(&raw[0]);
  if (!dev) { printf("OPENFAIL\n"); return 1; }
  LIBMTP_Get_Storage(dev, LIBMTP_STORAGE_SORTBY_NOTSORTED);
  storage = dev->storage->id;
  printf("CONNECTED %s\n#DONE\n", LIBMTP_Get_Friendlyname(dev)); fflush(stdout);

  char line[8192];
  while (fgets(line, sizeof line, stdin)) {
    line[strcspn(line, "\n")] = 0;
    char *cmd = strtok(line, "\t"), *a = strtok(NULL, "\t"), *b = strtok(NULL, "\t");
    if (!cmd || !*cmd) continue;
    uint32_t id; int folder; uint64_t sz;
    if (!strcmp(cmd, "quit")) break;
    else if (!strcmp(cmd, "ping")) printf("pong\n");
    else if (!a) printf("ERR missing arg\n");
    else if (!strcmp(cmd, "ls") || !strcmp(cmd, "tree")) {
      if (!*a || !strcmp(a, "/")) { id = LIBMTP_FILES_AND_FOLDERS_ROOT; folder = 1; }
      else if (resolve(a, &id, &folder, NULL)) { printf("ERR notfound %s\n", a); goto done; }
      if (!folder) printf("ERR notfolder\n"); else tree(id, "", cmd[0] == 't');
    } else if (!strcmp(cmd, "get") && b) {
      if (resolve(a, &id, &folder, NULL)) printf("ERR notfound %s\n", a);
      else printf("%s\n", get_rec(id, folder, b) ? "GET-ERRORS" : "OK");
    } else if (!strcmp(cmd, "rm")) {
      if (resolve(a, &id, &folder, NULL)) printf("ERR notfound %s\n", a);
      else if (folder) printf("ERR refusing to delete folder\n");
      else { int r = LIBMTP_Delete_Object(dev, id); printf("%s rm %s\n", r ? "ERR" : "OK", a); if (r) LIBMTP_Dump_Errorstack(dev), LIBMTP_Clear_Errorstack(dev); }
    } else if (!strcmp(cmd, "rmrf")) {
      // Safety: only allow deep paths (at least 2 components) and never the koreader root.
      if (!strchr(a, '/') ) printf("ERR refusing top-level path\n");
      else if (resolve(a, &id, &folder, NULL)) printf("ERR notfound %s\n", a);
      else printf("%s rmrf %s\n", rm_rec(id, folder, a) ? "ERR" : "OK", a);
    } else if (!strcmp(cmd, "put") && b) {
      struct stat st; if (stat(a, &st)) { printf("ERR nolocal %s\n", a); goto done; }
      if (resolve(b, &id, &folder, NULL) || !folder) { printf("ERR nodir %s\n", b); goto done; }
      char tmp[4096]; strncpy(tmp, a, sizeof tmp - 1); tmp[sizeof tmp - 1] = 0;
      char *name = basename(tmp);
      uint32_t old; int of;
      char full[4096]; snprintf(full, sizeof full, "%s/%s", b, name);
      if (!resolve(full, &old, &of, NULL)) { printf("ERR exists %s (rm first)\n", full); goto done; }
      LIBMTP_file_t *fd = LIBMTP_new_file_t();
      fd->filename = strdup(name); fd->filesize = st.st_size; fd->filetype = LIBMTP_FILETYPE_UNKNOWN;
      fd->parent_id = id; fd->storage_id = storage;
      int r = LIBMTP_Send_File_From_File(dev, a, fd, NULL, NULL);
      printf("%s put %s\n", r ? "ERR" : "OK", full);
      if (r) LIBMTP_Dump_Errorstack(dev), LIBMTP_Clear_Errorstack(dev);
      LIBMTP_destroy_file_t(fd);
    } else printf("ERR unknown %s\n", cmd);
  done:
    printf("#DONE\n"); fflush(stdout);
  }
  LIBMTP_Release_Device(dev);
  printf("BYE\n");
  return 0;
}
