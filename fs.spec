perms is a bit flag:
    - execute (x) -> 1
    - write (w) -> 2
    - read (r) -> 4

fs:open(path, mode, userId) -> Stream
fs:checkPermissions(item, userId, accessType) -> wether a user has required perms for path
fs:Permissions(path, userId) -> what perms a user has for a path 
fs:list(path, userId) -> files in a path (needs r--)
fs:makeDir(path, usr) -> creates a dir (needs -w-)
fs:exec(path, userId) -> func for the file (needs --x)
fs:delete(path, usr) -> deletes a path (needs -w-)