import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getTheatres from '@salesforce/apex/BookingController.getTheatres';
import getMoviesByTheatre from '@salesforce/apex/BookingController.getMoviesByTheatre';
import createNewMovie from '@salesforce/apex/BookingController.createNewMovie';
import createBooking from '@salesforce/apex/BookingController.createBooking';
import getShowTimeOptions from '@salesforce/apex/BookingController.getShowTimeOptions';
import getSeatsBySlot from '@salesforce/apex/BookingController.getSeatsBySlot';

export default class MovieBookingForm extends LightningElement {

    // ============================================
    // STATE VARIABLES
    // ============================================
    @track theatres        = [];
    @track movies          = [];
    @track filteredMovies  = [];
    @track movieSearchTerm = '';
    @track showMovieDropdown      = false;
    @track isMovieSearchDisabled  = true;
    @track bookedSeats    = '--';
    @track availableSeats = '--';
    @track emailError     = '';
    @track showTimeOptions = [];
    @track isLoading      = false;
    @track dateError      = '';

    @track formData = {
        firstName    : '',
        lastName     : '',
        email        : '',
        phone        : '',
        theatreId    : '',
        movieId      : '',
        showTime     : '',
        ticketType   : '',
        ticketPrice  : 0,
        numberOfSeats: 1,
        paymentMode  : '',
        bookingDate  : '',
    };


    // ============================================
    // LIFECYCLE
    // ============================================
    connectedCallback() {
        this.loadTheatres();
        this.loadShowTimes();
    }

    loadShowTimes() {
        getShowTimeOptions()
            .then(result => { this.showTimeOptions = result; })
            .catch(error => {
                this.showToast('Error', 'Failed to load show times', 'error');
                console.error('Show times error:', error);
            });
    }

    loadTheatres() {
        this.isLoading = true;
        getTheatres()
            .then(result => { this.theatres = result; })
            .catch(error => {
                this.showToast('Error', 'Failed to load theatres', 'error');
                console.error('Load theatres error:', error);
            })
            .finally(() => { this.isLoading = false; });
    }


    // ============================================
    // COMPUTED
    // ============================================
    get totalAmount() {
        const seats = parseInt(this.formData.numberOfSeats) || 0;
        const price = parseFloat(this.formData.ticketPrice)  || 0;
        return (seats * price).toFixed(2);
    }

    get showAddNewOption() {
        if (!this.movieSearchTerm || !this.movieSearchTerm.trim()) return false;
        const lower = this.movieSearchTerm.trim().toLowerCase();
        return !this.movies.some(m => m.Name.toLowerCase() === lower);
    }

    get noMoviesAtAll() {
        return this.movies.length === 0 &&
               (!this.movieSearchTerm || !this.movieSearchTerm.trim());
    }

    get todayDate() {
        const today = new Date();
        const yyyy  = today.getFullYear();
        const mm    = String(today.getMonth() + 1).padStart(2, '0');
        const dd    = String(today.getDate()).padStart(2, '0');
        return `${yyyy}-${mm}-${dd}`;
    }


    // ============================================
    // HANDLER: Generic input
    // ============================================
    handleInputChange(event) {
        const field = event.target.dataset.field;
        const value = event.target.value;
        this.formData = { ...this.formData, [field]: value };
    }


    // ============================================
    // HANDLER: Theatre change
    // ============================================
    handleTheatreChange(event) {
        const theatreId = event.target.value;
        this.formData = { 
            ...this.formData, 
            theatreId, 
            movieId     : '', 
            showTime    : '',
            bookingDate : ''
        };
        this.movieSearchTerm       = '';
        this.movies                = [];
        this.filteredMovies        = [];
        this.bookedSeats           = '--';
        this.availableSeats        = '--';
        this.dateError             = '';

        if (!theatreId) {
            this.isMovieSearchDisabled = true;
            return;
        }

        this.isLoading = true;
        getMoviesByTheatre({ theatreId })
            .then(result => {
                this.movies                = result;
                this.filteredMovies        = result;
                this.isMovieSearchDisabled = false;
                if (result.length === 0) {
                    this.showToast('Info', 'No movies yet. Type to add a new one.', 'info');
                }
            })
            .catch(error => {
                this.showToast('Error', 'Failed to load movies', 'error');
                console.error('Load movies error:', error);
            })
            .finally(() => { this.isLoading = false; });
    }


    // ============================================
    // HANDLER: Movie typeahead search
    // ✅ FIX: exact match असल्यास movieId clear होणार नाही
    // ============================================
    handleMovieSearch(event) {
        const searchTerm = event.target.value || '';
        this.movieSearchTerm = searchTerm;

        // Exact match आहे का check कर — असल्यास movieId clear नको
        const exactMatch = this.movies.find(
            m => m.Name.toLowerCase() === searchTerm.toLowerCase()
        );

        if (!exactMatch && this.formData.movieId) {
            this.formData       = { ...this.formData, movieId: '', showTime: '' };
            this.bookedSeats    = '--';
            this.availableSeats = '--';
        }

        if (!searchTerm.trim()) {
            this.filteredMovies = this.movies;
        } else {
            const term = searchTerm.toLowerCase();
            this.filteredMovies = this.movies.filter(m =>
                m.Name.toLowerCase().includes(term)
            );
        }

        this.showMovieDropdown = true;
    }

    // ✅ FIX: 300ms — mousedown event आधी complete होण्यासाठी
    handleMovieBlur() {
        setTimeout(() => { this.showMovieDropdown = false; }, 300);
    }


    // ============================================
    // HANDLER: Existing movie select
    // ✅ FIX: dropdown आधी बंद कर, मग formData update कर
    // ============================================
    handleMovieSelect(event) {
        const movieId   = event.currentTarget.dataset.id;
        const movieName = event.currentTarget.dataset.name;

        this.showMovieDropdown = false; // ← आधी बंद कर
        this.movieSearchTerm   = movieName;

        this.formData = { ...this.formData, movieId };

        this.bookedSeats    = '--';
        this.availableSeats = '--';

        if (this.formData.showTime && this.formData.bookingDate) {
            this.loadSlotSeats();
        }
    }


    // ============================================
    // HANDLER: Add New Movie
    // ============================================
    handleAddNewMovie() {
        const newMovieName = this.movieSearchTerm.trim();

        if (!newMovieName) {
            this.showToast('Error', 'Please enter a movie name', 'error');
            return;
        }
        if (!this.formData.theatreId) {
            this.showToast('Error', 'Please select a theatre first', 'error');
            return;
        }

        const lower    = newMovieName.toLowerCase();
        const existing = this.movies.find(m => m.Name.toLowerCase() === lower);
        if (existing) {
            this.showMovieDropdown = false;
            this.movieSearchTerm   = existing.Name;
            this.formData = { ...this.formData, movieId: existing.Id };
            if (this.formData.showTime && this.formData.bookingDate) this.loadSlotSeats();
            this.showToast('Info', `"${existing.Name}" already exists. Selected!`, 'info');
            return;
        }

        // eslint-disable-next-line no-alert
        if (!confirm(`Create new movie "${newMovieName}"?`)) return;

        this.isLoading         = true;
        this.showMovieDropdown = false;

        createNewMovie({ movieName: newMovieName, theatreId: this.formData.theatreId })
            .then(newMovie => {
                this.movies          = [...this.movies, newMovie];
                this.filteredMovies  = this.movies;
                this.movieSearchTerm = newMovie.Name;
                this.formData = { ...this.formData, movieId: newMovie.Id };
                this.bookedSeats    = '--';
                this.availableSeats = '--';
                if (this.formData.showTime && this.formData.bookingDate) this.loadSlotSeats();
                this.showToast('Success!', `Movie "${newMovie.Name}" created & selected!`, 'success');
            })
            .catch(error => {
                const msg = error.body?.message || 'Failed to create movie';
                this.showToast('Error', msg, 'error');
                console.error('Create movie error:', error);
            })
            .finally(() => { this.isLoading = false; });
    }


    // ============================================
    // HANDLER: Show Time change
    // ============================================
    handleShowTimeChange(event) {
        const showTime = event.target.value;
        this.formData = { ...this.formData, showTime };

        if (!showTime) {
            this.bookedSeats    = '--';
            this.availableSeats = '--';
            return;
        }

        this.loadSlotSeats();
    }


    // ============================================
    // HANDLER: Date change
    // ============================================
    handleDateChange(event) {
        const dateStr = event.target.value;
        this.formData = { ...this.formData, bookingDate: dateStr };
        this.dateError = '';

        if (!dateStr) return;

        const selected = new Date(dateStr);
        const today    = new Date();
        today.setHours(0, 0, 0, 0);

        if (selected < today) {
            this.dateError = 'Booking Date cannot be a past date.';
            this.formData  = { ...this.formData, bookingDate: '' };
            this.bookedSeats    = '--';
            this.availableSeats = '--';
            return;
        }

        if (this.formData.movieId && this.formData.showTime) {
            this.loadSlotSeats();
        }
    }


    // ============================================
    // CORE: Slot-wise seats load
    // ============================================
    loadSlotSeats() {
        const { movieId, theatreId, showTime, bookingDate } = this.formData;
        if (!movieId || !theatreId || !showTime || !bookingDate) return;

        const apexDate = new Date(bookingDate);
        const yyyy = apexDate.getFullYear();
        const mm   = String(apexDate.getMonth() + 1).padStart(2, '0');
        const dd   = String(apexDate.getDate()).padStart(2, '0');
        const formattedDate = `${yyyy}-${mm}-${dd}`;

        this.isLoading = true;
        getSeatsBySlot({ movieId, theatreId, showTime, bookingDate: formattedDate })
            .then(result => {
                if (result) {
                    this.bookedSeats    = result.bookedSeats;
                    this.availableSeats = result.availableSeats;
                }
            })
            .catch(error => {
                console.error('Slot seats error:', error);
                this.showToast('Error', 'Failed to load seat info', 'error');
                this.bookedSeats    = '--';
                this.availableSeats = '--';
            })
            .finally(() => { this.isLoading = false; });
    }


    // ============================================
    // HANDLER: Ticket Type
    // ============================================
    handleTicketTypeChange(event) {
        const type = event.target.value;
        const priceMap = { Silver: 150, Gold: 250, Platinum: 300 };
        this.formData = { ...this.formData, ticketType: type, ticketPrice: priceMap[type] || 0 };
    }


    // ============================================
    // HANDLER: Seats input
    // ============================================
    handleSeatsChange(event) {
        let seats = parseInt(event.target.value) || 1;
        if (seats < 1) seats = 1;
        if (seats > 10) {
            seats = 10;
            this.showToast('Warning', 'Maximum 10 seats per booking', 'warning');
        }
        if (typeof this.availableSeats === 'number' && seats > this.availableSeats) {
            this.showToast('Warning', `Only ${this.availableSeats} seats available for this slot`, 'warning');
            seats = this.availableSeats;
        }
        this.formData = { ...this.formData, numberOfSeats: seats };
    }


    // ============================================
    // VALIDATION: Email
    // ============================================
    validateEmail() {
        const email = this.formData.email;
        if (!email) { this.emailError = ''; return true; }
        const regex = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/;
        if (!regex.test(email)) {
            this.emailError = 'Please enter a valid email address';
            return false;
        }
        this.emailError = '';
        return true;
    }


    // ============================================
    // VALIDATION: Full form
    // ============================================
    validateForm() {
        const d = this.formData;
        if (!d.firstName?.trim())   { this.showToast('Error', 'First Name is required', 'error');        return false; }
        if (!d.lastName?.trim())    { this.showToast('Error', 'Last Name is required', 'error');         return false; }
        if (!d.email?.trim())       { this.showToast('Error', 'Email is required', 'error');             return false; }
        if (!this.validateEmail())  { this.showToast('Error', 'Enter a valid email', 'error');           return false; }
        if (!d.phone || d.phone.toString().replace(/\D/g, '').length !== 10) {
            this.showToast('Error', 'Enter a valid 10-digit phone', 'error');                            return false;
        }
        if (!d.theatreId)           { this.showToast('Error', 'Please select a theatre', 'error');      return false; }
        if (!d.movieId)             { this.showToast('Error', 'Please select or add a movie', 'error'); return false; }
        if (!d.showTime)            { this.showToast('Error', 'Please select show time', 'error');      return false; }
        if (!d.bookingDate)         { this.showToast('Error', 'Please select booking date', 'error');   return false; }
        const selectedDate = new Date(d.bookingDate);
        const today = new Date(); today.setHours(0, 0, 0, 0);
        if (selectedDate < today)   { this.showToast('Error', 'Booking Date cannot be a past date', 'error'); return false; }
        if (!d.ticketType)          { this.showToast('Error', 'Please select ticket type', 'error');    return false; }
        if (!d.numberOfSeats || d.numberOfSeats < 1) {
            this.showToast('Error', 'Select at least 1 seat', 'error');                                 return false;
        }
        if (!d.paymentMode)         { this.showToast('Error', 'Please select payment mode', 'error');   return false; }
        if (typeof this.availableSeats === 'number' && d.numberOfSeats > this.availableSeats) {
            this.showToast('Error', `Only ${this.availableSeats} seats available for this show`, 'error'); return false;
        }
        return true;
    }


    // ============================================
    // HANDLER: Confirm Booking
    // ============================================
    handleConfirmBooking() {
        if (!this.validateForm()) return;

        this.isLoading = true;
        const bookingData = {
            firstName    : this.formData.firstName,
            lastName     : this.formData.lastName,
            email        : this.formData.email,
            phone        : this.formData.phone,
            theatreId    : this.formData.theatreId,
            movieId      : this.formData.movieId,
            showTime     : this.formData.showTime,
            bookingDate  : this.formData.bookingDate,
            ticketType   : this.formData.ticketType,
            ticketPrice  : this.formData.ticketPrice,
            numberOfSeats: parseInt(this.formData.numberOfSeats),
            paymentMode  : this.formData.paymentMode,
            totalAmount  : parseFloat(this.totalAmount)
        };

        createBooking({ bookingData })
            .then(bookingId => {
                this.showToast('Booking Confirmed! 🎉', `Booking saved. ID: ${bookingId}`, 'success');
                this.loadSlotSeats();
                this.resetFormKeepSlot();
            })
            .catch(error => {
                const msg = error.body?.message || 'Unknown error occurred';
                this.showToast('Booking Failed', msg, 'error');
                console.error('Booking error:', error);
            })
            .finally(() => { this.isLoading = false; });
    }


    // ============================================
    // UTILITY: Full reset
    // ============================================
    resetForm() {
        this.formData = {
            firstName: '', lastName: '', email: '', phone: '',
            theatreId: '', movieId: '', showTime: '', bookingDate: '',
            ticketType: '', ticketPrice: 0, numberOfSeats: 1, paymentMode: ''
        };
        this.movieSearchTerm       = '';
        this.movies                = [];
        this.filteredMovies        = [];
        this.bookedSeats           = '--';
        this.availableSeats        = '--';
        this.isMovieSearchDisabled = true;
        this.emailError            = '';
        this.dateError             = '';
        this.template.querySelectorAll('select').forEach(s => { s.value = ''; });
        this.template.querySelectorAll('input').forEach(i => {
            if (i.type !== 'number') i.value = '';
        });
    }


    // ============================================
    // UTILITY: Reset — slot same ठेव
    // ============================================
    resetFormKeepSlot() {
        this.formData = {
            ...this.formData,
            firstName    : '',
            lastName     : '',
            email        : '',
            phone        : '',
            ticketType   : '',
            ticketPrice  : 0,
            numberOfSeats: 1,
            paymentMode  : ''
        };
        this.emailError = '';
        this.dateError  = '';
    }


    // ============================================
    // UTILITY: Toast
    // ============================================
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}