# XWinTab patché (fork autonome)

Ce dossier doit contenir la **source XWinTab patchée** qui fait marcher Flash/Animate
(les 7 correctifs documentés dans `PATCHES.md`), appliqués sur XWinTab de Graham--M.

## Y déposer la source (depuis ta machine de travail)

```bash
cp -r ~/softs/xwintab/XWinTab/src           ./xwintab/src
cp    ~/softs/xwintab/XWinTab/build32-def.sh ./xwintab/build32-def.sh
# + le LICENSE/COPYING d'upstream, et tout fichier de build nécessaire
```

`install.sh` lancera `./build32-def.sh` ici, puis copiera `wintab32.dll` +
`XWinTabHelper.dll.so` dans le system32 du prefix.

Les artefacts de build (`wintab32.dll`, `XWinTabHelper.dll.so`, `*.o`) sont gitignorés.
