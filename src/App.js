import React, { useState, useEffect } from 'react';
import { Container, Navbar, Nav, ListGroup, Button, Alert } from 'react-bootstrap';
import 'bootstrap/dist/css/bootstrap.min.css';
import '../assets/style.css';

const api = 'putapinamehere/'

function App() {
  const [title, setTitle] = useState('Default Title');
  const [user, setUser] = useState(null);
  const [pages, setPages] = useState([]);

  useEffect(() => {
    // Fetch data here and set states accordingly
    // TODO: Make this filled in by api rather than hardcode
    setTitle('My Dynamic Title');
    setUser({ email: 'user@example.com' });
    setPages([
      { dir: 'page1', title: 'Page 1' },
      { dir: 'page2', title: 'Page 2' },
    ]);
  }, []);

  return (
    <div>
      <Navbar bg="dark" variant="dark" expand="lg">
        <Container>
          <Navbar.Brand href="#home">{title}</Navbar.Brand>
          <Navbar.Toggle aria-controls="basic-navbar-nav" />
          <Navbar.Collapse id="basic-navbar-nav">
            <Nav className="ms-auto">
              {user ? (
                <Nav.Link href="/logout" className="ms-3">Logout</Nav.Link>
              ) : (
                <Nav.Link href="/login" className="ms-3">Login</Nav.Link>
              )}
            </Nav>
          </Navbar.Collapse>
        </Container>
      </Navbar>


      <Container className="text-center mt-4">
        {user ? (
          <>
            {pages.length > 0 ? (
              <ListGroup>
                {pages.map((page) => (
                  <ListGroup.Item key={page.dir}>
                    <a href={`/p/${page.dir}/index.html`}>{page.title}</a>
                  </ListGroup.Item>
                ))}
              </ListGroup>
            ) : (
              <Alert variant="warning">No pages to display</Alert>
            )}
            <p className="mt-3">You are signed in as {user.email}.</p>
          </>
        ) : (
          <Button variant="primary" href="/login">Login to view documents...</Button>
        )}
        <footer className="mt-5">
          <p>
            Powered by <a href="https://github.com/newAM/oidc_pages">OIDC Pages</a>, licensed under the{' '}
            <a href="https://spdx.org/licenses/AGPL-3.0-or-later.html">AGPL-3.0-or-later</a>
          </p>
        </footer>
      </Container>
    </div>
  );
}

export default App;
