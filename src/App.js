import React, { useState, useEffect } from 'react';
import { Container, Navbar, Nav, Row, Col, Alert, Button, OverlayTrigger, Tooltip, ListGroup, ListGroupItem } from 'react-bootstrap';
import ListItemCard from './components/ListItemCard';
import 'bootstrap/dist/css/bootstrap.min.css';
import '../assets/style.css';

function App() {
  const [title, setTitle] = useState('Default Title');
  const [user, setUser] = useState(null);
  const [pages, setPages] = useState([]);
  const [isPreview, setIsPreview] = useState(true);

  useEffect(() => {
    // Fetch data here and set states accordingly
    // This is a mock example. Replace with actual data fetching logic.
    setTitle('My Dynamic Title');
    setUser({ email: 'user@example.com' });
    setPages([
      { dir: 'page1', title: 'Page 1', image: 'https://via.placeholder.com/150' },
      { dir: 'page2', title: 'Page 2', image: 'https://via.placeholder.com/150' },
    ]);
  }, []);

  const handleToggleView = () => {
    setIsPreview(!isPreview);
  };

  return (
    <div>
      <Navbar bg="dark" variant="dark" expand="lg">
        <Container>
          <Navbar.Brand href="#home">{title}</Navbar.Brand>
          <Navbar.Toggle aria-controls="basic-navbar-nav" />
          <Navbar.Collapse id="basic-navbar-nav">
            <Nav className="ms-auto">
              <Button variant="outline-light" onClick={handleToggleView} className="ms-3">
                {isPreview ? 'List View' : 'Preview View'}
              </Button>
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
              isPreview ? (
                <Row>
                  {pages.map((page) => (
                    <Col key={page.dir} xs={12} md={6} lg={4}>
                      <ListItemCard page={page} />
                    </Col>
                  ))}
                </Row>
              ) : (
                <ListGroup>
                  {pages.map((page) => (
                    <OverlayTrigger
                      key={page.dir}
                      placement="bottom"
                      overlay={
                        <Tooltip id={`tooltip-${page.dir}`}>
                          <img src={page.image} alt={page.title} width="150" />
                        </Tooltip>
                      }
                    >
                      <ListGroup.Item>
                        <a href={`/p/${page.dir}/index.html`}>{page.title}</a>
                      </ListGroup.Item>
                    </OverlayTrigger>
                  ))}
                </ListGroup>
              )
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
