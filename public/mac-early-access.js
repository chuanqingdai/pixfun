(() => {
  'use strict';
  const form=document.getElementById('applicationForm'),submit=document.getElementById('applySubmit');
  const background=document.getElementById('background'),platforms=document.getElementById('platformChoices'),error=document.getElementById('applicationError');
  function syncPlatforms(){platforms.hidden=!['creator','editor','studio','brand'].includes(background.value);}
  background.addEventListener('change',syncPlatforms);syncPlatforms();
  let sending=false;
  form.addEventListener('submit',async event=>{
    event.preventDefault();
    if(sending||!form.reportValidity())return;
    if(!/^https?:$/.test(location.protocol)){error.textContent='Open this page through the Pixfun website to submit your application.';error.hidden=false;error.focus();return;}
    sending=true;submit.disabled=true;submit.textContent='Sending…';form.setAttribute('aria-busy','true');error.hidden=true;
    const controller=new AbortController(),timeout=setTimeout(()=>controller.abort(),15000);
    try{
      const response=await fetch('/api/mac-applications',{method:'POST',headers:{'Content-Type':'application/json'},credentials:'same-origin',signal:controller.signal,body:JSON.stringify({background:background.value,platforms:platforms.hidden?[]:[...form.querySelectorAll('[name="platforms"]:checked')].map(input=>input.value),need:form.need.value.trim(),email:form.email.value.trim(),budgetRange:form.querySelector('[name="budgetRange"]:checked').value,contactConsent:document.getElementById('contactConsent').checked,website:document.getElementById('website').value})});
      const data=await response.json().catch(()=>null);
      if(!response.ok||data?.ok!==true)throw new Error(data?.error||'Your application could not be saved. Please try again.');
      form.hidden=true;document.querySelector('.application-intro').hidden=true;
      document.getElementById('applicationSuccess').hidden=false;document.getElementById('successTitle').focus();
      form.reset();syncPlatforms();
    }catch(problem){error.textContent=problem.name==='AbortError'?'The request timed out. Please try again; repeat submissions will not create duplicates.':problem.message==='Failed to fetch'?'Unable to connect. Check your connection and try again.':problem.message;error.hidden=false;error.focus();}
    finally{clearTimeout(timeout);sending=false;submit.disabled=false;submit.textContent='Send application ↗';form.removeAttribute('aria-busy');}
  });
})();
