/**
 * BookingControllerTest
 * --------------------------------------------------
 * Comprehensive test class — 90%+ coverage.
 * Positive + Negative + Bulk + Governor limit scenarios.
 * 
 * @author  Shrikant Khedkar
 * @date    May 2026
 */
@isTest
private class BookingControllerTest {
    
    // ============================================
    // TEST DATA SETUP
    // ============================================
    @testSetup
    static void setupTestData() {
        Theatre__c theatre = new Theatre__c(
            Name = 'Test PVR',
            Theatre_Capacity__c = 100
        );
        insert theatre;
        
        Movie__c movie = new Movie__c(
            Name = 'Test Movie',
            Theatre__c = theatre.Id,
            Duration__c = 2.30,
            Ticket_Price__c = 250,
            Booked_Seats__c = 0
        );
        insert movie;
    }
    
    
    // ============================================
    // POSITIVE TESTS
    // ============================================
    
    @isTest
    static void testGetTheatres() {
        Test.startTest();
        List<Theatre__c> theatres = BookingController.getTheatres();
        Test.stopTest();
        
        System.assertEquals(1, theatres.size(), 'Ek theatre asla pahije');
        System.assertEquals('Test PVR', theatres[0].Name);
    }
    
    @isTest
    static void testGetMoviesByTheatre() {
        Theatre__c t = [SELECT Id FROM Theatre__c LIMIT 1];
        
        Test.startTest();
        List<Movie__c> movies = BookingController.getMoviesByTheatre(t.Id);
        Test.stopTest();
        
        System.assertEquals(1, movies.size(), 'Ek movie asla pahije');
    }
    
    @isTest
    static void testGetMoviesByTheatreBlank() {
        Test.startTest();
        List<Movie__c> movies = BookingController.getMoviesByTheatre(null);
        Test.stopTest();
        
        System.assertEquals(0, movies.size(), 'Empty list asla pahije');
    }
    
    @isTest
    static void testGetMovieDetails() {
        Movie__c m = [SELECT Id FROM Movie__c LIMIT 1];
        
        Test.startTest();
        Movie__c result = BookingController.getMovieDetails(m.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, result);
        System.assertEquals('Test Movie', result.Name);
    }
    
    @isTest
    static void testGetMovieDetailsBlank() {
        Test.startTest();
        Movie__c result = BookingController.getMovieDetails(null);
        Test.stopTest();
        
        System.assertEquals(null, result);
    }
    
    @isTest
    static void testCreateBookingSuccess() {
        Theatre__c t = [SELECT Id FROM Theatre__c LIMIT 1];
        Movie__c m = [SELECT Id FROM Movie__c LIMIT 1];
        BookingController.BookingWrapper data = buildValidBooking(t.Id, m.Id);
        
        Test.startTest();
        String bookingId = BookingController.createBooking(data);
        Test.stopTest();
        
        System.assertNotEquals(null, bookingId, 'Booking ID return zala pahije');
        
        List<Contact> contacts = [SELECT Id FROM Contact WHERE Email = 'test@example.com'];
        System.assertEquals(1, contacts.size(), 'Contact create zala pahije');
        
        List<Booking__c> bookings = [SELECT Id FROM Booking__c];
        System.assertEquals(1, bookings.size(), 'Booking create zala pahije');
    }
    
    @isTest
    static void testCreateBookingExistingContact() {
        Contact existing = new Contact(
            FirstName = 'Old',
            LastName = 'Name',
            Email = 'test@example.com',
            Phone = '1111111111'
        );
        insert existing;
        
        Theatre__c t = [SELECT Id FROM Theatre__c LIMIT 1];
        Movie__c m = [SELECT Id FROM Movie__c LIMIT 1];
        BookingController.BookingWrapper data = buildValidBooking(t.Id, m.Id);
        
        Test.startTest();
        BookingController.createBooking(data);
        Test.stopTest();
        
        Contact updated = [SELECT FirstName FROM Contact WHERE Email = 'test@example.com'];
        System.assertEquals('Shrikant', updated.FirstName, 
            'Existing contact update zala pahije');
        
        // Faqt 1 contact asla pahije (duplicate nako)
        Integer count = [SELECT COUNT() FROM Contact WHERE Email = 'test@example.com'];
        System.assertEquals(1, count, 'Duplicate contact nako');
    }
    
    
    // ============================================
    // BULK TEST — 50 bookings ek shot madhe
    // ============================================
    @isTest
    static void testBulkBookings() {
        // Bigger theatre + movie sathi
        Theatre__c bigTheatre = new Theatre__c(
            Name = 'Big Theatre',
            Theatre_Capacity__c = 500
        );
        insert bigTheatre;
        
        Movie__c bigMovie = new Movie__c(
            Name = 'Bulk Movie',
            Theatre__c = bigTheatre.Id,
            Duration__c = 2.30,
            Ticket_Price__c = 250,
            Booked_Seats__c = 0
        );
        insert bigMovie;
        
        // 50 bookings prepare kar
        List<BookingController.BookingWrapper> wrappers = 
            new List<BookingController.BookingWrapper>();
        
        for (Integer i = 0; i < 50; i++) {
            BookingController.BookingWrapper data = buildValidBooking(
                bigTheatre.Id, bigMovie.Id
            );
            data.email = 'bulk' + i + '@example.com';
            data.numberOfSeats = 2;
            wrappers.add(data);
        }
        
        Test.startTest();
        List<String> ids = BookingService.saveBookingsBulk(wrappers);
        Test.stopTest();
        
        System.assertEquals(50, ids.size(), '50 bookings save zali pahijet');
        
        // Verify saglya bookings
        Integer bookingCount = [SELECT COUNT() FROM Booking__c];
        System.assertEquals(50, bookingCount);
        
        // Verify saglya contacts
        Integer contactCount = [SELECT COUNT() FROM Contact WHERE Email LIKE 'bulk%'];
        System.assertEquals(50, contactCount);
    }
    
    
    // ============================================
    // NEGATIVE TESTS — Validations
    // ============================================
    
    @isTest
    static void testValidation_BlankFirstName() {
        runValidationTest('firstName', '');
    }
    
    @isTest
    static void testValidation_BlankLastName() {
        runValidationTest('lastName', '');
    }
    
    @isTest
    static void testValidation_BlankEmail() {
        runValidationTest('email', '');
    }
    
    @isTest
    static void testValidation_InvalidEmail() {
        runValidationTest('email', 'invalid-email');
    }
    
    @isTest
    static void testValidation_BlankPhone() {
        runValidationTest('phone', '');
    }
    
    @isTest
    static void testValidation_InvalidPhone() {
        runValidationTest('phone', '123');
    }
    
    @isTest
    static void testValidation_BlankTheatre() {
        runValidationTest('theatreId', '');
    }
    
    @isTest
    static void testValidation_BlankShowTime() {
        runValidationTest('showTime', '');
    }
    
    @isTest
    static void testValidation_BlankTicketType() {
        runValidationTest('ticketType', '');
    }
    
    @isTest
    static void testValidation_ZeroSeats() {
        runValidationTest('numberOfSeats', 0);
    }
    
    @isTest
    static void testValidation_TooManySeats() {
        runValidationTest('numberOfSeats', 15);
    }
    
    @isTest
    static void testValidation_BlankPayment() {
        runValidationTest('paymentMode', '');
    }
    
    
    // ============================================
    // INSUFFICIENT SEATS TEST
    // ============================================
    @isTest
    static void testInsufficientSeats() {
        // Small capacity theatre
        Theatre__c smallTheatre = new Theatre__c(
            Name = 'Small',
            Theatre_Capacity__c = 5
        );
        insert smallTheatre;
        
        Movie__c smallMovie = new Movie__c(
            Name = 'Small Movie',
            Theatre__c = smallTheatre.Id,
            Duration__c = 2.30,
            Ticket_Price__c = 250,
            Booked_Seats__c = 0
        );
        insert smallMovie;
        
        // Aadhi 4 seats book kar
        BookingController.BookingWrapper first = buildValidBooking(
            smallTheatre.Id, smallMovie.Id
        );
        first.numberOfSeats = 4;
        first.email = 'first@example.com';
        BookingController.createBooking(first);
        
        // Aata 3 seats book karaycha try kar (faqt 1 available ahe)
        BookingController.BookingWrapper second = buildValidBooking(
            smallTheatre.Id, smallMovie.Id
        );
        second.numberOfSeats = 3;
        second.email = 'second@example.com';
        
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            BookingController.createBooking(second);
        } catch (Exception e) {
            exceptionThrown = true;
            System.assert(
                e.getMessage().contains('available'), 
                'Insufficient seats message yaychi'
            );
        }
        Test.stopTest();
        
        System.assertEquals(true, exceptionThrown, 
            'Insufficient seats exception aali pahije');
    }
    
    
    // ============================================
    // NULL DATA TEST
    // ============================================
    @isTest
    static void testNullData() {
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            BookingController.createBooking(null);
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        
        System.assertEquals(true, exceptionThrown, 
            'Null data var exception yayla pahije');
    }
    
    
    // ============================================
    // HELPER METHODS
    // ============================================
    
    private static BookingController.BookingWrapper buildValidBooking(
        Id theatreId, Id movieId
    ) {
        BookingController.BookingWrapper data = new BookingController.BookingWrapper();
        data.firstName = 'Shrikant';
        data.lastName = 'Khedkar';
        data.email = 'test@example.com';
        data.phone = '9876543210';
        data.theatreId = theatreId;
        data.movieId = movieId;
        data.showTime = '6:00 PM';
        data.ticketType = 'Gold';
        data.ticketPrice = 250;
        data.numberOfSeats = 2;
        data.paymentMode = 'UPI';
        data.totalAmount = 500;
        return data;
    }
    
    /**
     * Generic validation test runner.
     * Field name + invalid value de, exception expect karto.
     */
    private static void runValidationTest(String fieldName, Object invalidValue) {
        Theatre__c t = [SELECT Id FROM Theatre__c LIMIT 1];
        Movie__c m = [SELECT Id FROM Movie__c LIMIT 1];
        BookingController.BookingWrapper data = buildValidBooking(t.Id, m.Id);
        
        // Reflection sarkha — field set kar
        if (fieldName == 'firstName') data.firstName = (String) invalidValue;
        else if (fieldName == 'lastName') data.lastName = (String) invalidValue;
        else if (fieldName == 'email') data.email = (String) invalidValue;
        else if (fieldName == 'phone') data.phone = (String) invalidValue;
        else if (fieldName == 'theatreId') data.theatreId = (String) invalidValue;
        else if (fieldName == 'showTime') data.showTime = (String) invalidValue;
        else if (fieldName == 'ticketType') data.ticketType = (String) invalidValue;
        else if (fieldName == 'paymentMode') data.paymentMode = (String) invalidValue;
        else if (fieldName == 'numberOfSeats') data.numberOfSeats = (Integer) invalidValue;
        
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            BookingController.createBooking(data);
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        
        System.assertEquals(true, exceptionThrown, 
            fieldName + ' validation fail honari');
    }
}