// When a wireframe is shown inside another page (the thumbnails in index.html), show only the iPad.
if (window.self !== window.top) document.documentElement.classList.add("embedded");
