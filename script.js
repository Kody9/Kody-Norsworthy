const projectImages = [
    ["images/fancychicksandeggs.png", "images/fancychicksandeggs2.png"],
    ["images/CRM1.png", "images/CRM2.png"],
    ["images/MERN-Library1.png", "images/MERN-Library2.png", "images/MERN-Library3.png"],
    ["images/Study1.png", "images/Study2.png", "images/Study3.png"]
];

let currentImageIndex = [0, 0, 0, 0]; // Initializes image index for each project

function changeSlide(direction, projectIndex) {
    currentImageIndex[projectIndex] += direction;
    let images = projectImages[projectIndex];
    if (currentImageIndex[projectIndex] >= images.length) {
        currentImageIndex[projectIndex] = 0; // Wrap around to the first image
    } else if (currentImageIndex[projectIndex] < 0) {
        currentImageIndex[projectIndex] = images.length - 1; // Wrap around to the last image
    }
    let projectItem = document.getElementsByClassName('project-item')[projectIndex];
    let img = projectItem.getElementsByClassName('project-image')[0];
    img.src = images[currentImageIndex[projectIndex]];
}

document.addEventListener('DOMContentLoaded', () => {
    // Initialize display with the first image of each project
    projectImages.forEach((images, index) => changeSlide(0, index));
});
