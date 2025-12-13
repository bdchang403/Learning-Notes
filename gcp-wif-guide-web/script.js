document.addEventListener('DOMContentLoaded', () => {

    // Sidebar Toggle
    const sidebar = document.getElementById('sidebar');
    const menuToggle = document.getElementById('menu-toggle');

    // Toggle sidebar on click
    menuToggle.addEventListener('click', () => {
        sidebar.classList.toggle('active');
        menuToggle.classList.toggle('moved');

        // Change icon (optional, simplified here)
    });

    // Close sidebar when clicking a link on mobile
    document.querySelectorAll('.nav-item').forEach(link => {
        link.addEventListener('click', () => {
            if (window.innerWidth < 1024) {
                sidebar.classList.remove('active');
                menuToggle.classList.remove('moved');
            }
        });
    });

    // Smooth scrolling for navigation links
    document.querySelectorAll('a[href^="#"]').forEach(anchor => {
        anchor.addEventListener('click', function (e) {
            e.preventDefault();
            document.querySelector(this.getAttribute('href')).scrollIntoView({
                behavior: 'smooth'
            });
        });
    });

    // Copy to clipboard functionality
    document.querySelectorAll('.copy-btn').forEach(button => {
        button.addEventListener('click', () => {
            const codeBlock = button.parentElement.querySelector('code');
            const codeText = codeBlock.innerText; // Preserves newlines

            navigator.clipboard.writeText(codeText).then(() => {
                const originalText = button.innerText;
                button.innerText = 'Copied!';
                setTimeout(() => {
                    button.innerText = originalText;
                }, 2000);
            }).catch(err => {
                console.error('Failed to copy: ', err);
            });
        });
    });

});
