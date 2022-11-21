window.addEventListener('DOMContentLoaded', (event) => {
    getVisitCount();
});


const localApi = 'http://localhost:7071/api/HttpTrigger1';
const functionApi = 'https://webapp01-prod-function.azurewebsites.net/api/HttpTrigger1?code=0_XQe2t_2YdlEXhDKKFu3H1L3qs4gjEmwc1xRxCm2CtaAzFuq1e5nQ==';

const getVisitCount = () => {
    let count = 30;
    document.getElementById('counter').innerText = "test " + count
    fetch(functionApi)
        .then(response => {
            return response.json()
        })
        .then(response => {
            console.log("Website called function API.");
            count = response.visitorCount;
            document.getElementById('counter').innerText = "Number of page views: " + count;
        }).catch(function (error) {
            console.log(error);
        });
    return count;
}
