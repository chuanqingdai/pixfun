(() => {
  if(!window.PixfunDesktop)return;
  document.documentElement.classList.add('desktop-app');
  document.title='Pixfun';
  const bar=document.createElement('div');bar.className='desktop-titlebar';bar.setAttribute('aria-hidden','true');bar.textContent='Pixfun';document.body.prepend(bar);
  document.querySelector('#libraryEmpty small').textContent='Original files stay in place · 100 files per batch';
  window.PixfunDesktop.onCommand(command=>{
    if(command==='import'||command==='folder'){if(window.PixfunLibrary.page==='home')window.PixfunWorkspace.attach(command==='folder');else window.PixfunLibrary.importNative(command==='folder');}
    else if(['home','media','skills','history'].includes(command))window.PixfunLibrary.navigate(command);
  });
})();
